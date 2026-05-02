//
//  RecommendationEngine.swift
//  AgenticHealthCoach
//

import Foundation
import SwiftData

@MainActor
struct RecommendationEngine {
    var client: GeminiClient = GeminiClient()

    /// Autonomous entry point — uses the latest real snapshot and the autonomous default config.
    func runOnce(container: ModelContainer) async {
        let context = container.mainContext
        guard let snapshot = latestSnapshot(context: context) else { return }
        _ = await runOnce(
            container: container,
            snapshot: snapshot,
            config: .autonomousDefault,
            simulatedNow: nil,
            bypassGuards: false,
            variantLabel: nil,
            blockTag: nil
        )
    }

    /// Shared path for autonomous + manual triggers.
    func runOnce(
        container: ModelContainer,
        snapshot: ContextSnapshot,
        config: PromptConfig,
        simulatedNow: Date?,
        bypassGuards: Bool,
        variantLabel: String?,
        blockTag: String?,
        forceNudge: Bool = false
    ) async -> Recommendation? {
        let context = container.mainContext

        let prefs = currentPreferences(context: context)
        let recent = bypassGuards ? [] : recentRecommendations(context: context, limit: 5)
        let now = simulatedNow ?? .now

        let prompt = buildPrompt(
            snapshot: snapshot,
            prefs: prefs,
            recent: recent,
            config: config,
            now: now,
            bypassGuards: bypassGuards,
            forceNudge: forceNudge
        )
        if bypassGuards {
            print("DEV outgoing manual recommendation prompt:\n\(prompt)")
        }

        let decision: AgentDecision
        do {
            decision = try await client.decide(prompt: prompt)
        } catch {
            return nil
        }

        let rawMessage = decision.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message: String
        if decision.action == .nudge, !rawMessage.isEmpty {
            message = rawMessage
        } else if forceNudge {
            // Model tried to stay quiet — synthesize a generic nudge so the user still sees one fire.
            message = !rawMessage.isEmpty ? rawMessage : "Quick check-in from your coach."
        } else {
            return nil
        }

        let goal = HealthGoal(rawValue: decision.goal ?? "") ?? prefs.goals.first ?? .activity
        let explanation = config.explanation == .with
            ? decision.explanation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            : ""
        let cleanedMessage = config.explanation == .without
            ? Self.stripTrailingRationale(from: message)
            : message
        let rec = Recommendation(
            timestamp: simulatedNow ?? .now,
            goal: goal,
            message: cleanedMessage,
            explanation: explanation,
            variantLabel: variantLabel,
            blockTag: blockTag
        )
        context.insert(rec)
        try? context.save()

        NotificationManager.shared.schedule(for: rec)
        PhoneConnectivityService.shared.send(WatchPayload(
            recommendationID: rec.persistentModelID.storeIdentifier ?? UUID().uuidString,
            goalDisplayName: rec.goal.displayName,
            message: rec.message,
            explanation: rec.explanation,
            timestamp: rec.timestamp,
            stepsToday: snapshot.stepsToday,
            sleepHoursLastNight: snapshot.sleepHoursLastNight,
            minutesUntilNextEvent: snapshot.minutesUntilNextEvent
        ))
        return rec
    }

    private func currentPreferences(context: ModelContext) -> UserPreferences {
        let descriptor = FetchDescriptor<UserPreferences>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let defaults = UserPreferences()
        context.insert(defaults)
        try? context.save()
        return defaults
    }

    private func latestSnapshot(context: ModelContext) -> ContextSnapshot? {
        var descriptor = FetchDescriptor<ContextSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func recentRecommendations(context: ModelContext, limit: Int) -> [Recommendation] {
        var descriptor = FetchDescriptor<Recommendation>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func buildPrompt(
        snapshot: ContextSnapshot,
        prefs: UserPreferences,
        recent: [Recommendation],
        config: PromptConfig,
        now: Date = .now,
        bypassGuards: Bool = false,
        forceNudge: Bool = false
    ) -> String {
        let signals = signalsBlock(snapshot: snapshot)

        // Raw override: user-provided system prompt fully replaces ours; signals are appended.
        if let override = config.systemPromptOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let prompt = """
            \(override)

            Available signals:
            \(signals)
            """
            print("DEV outgoing recommendation override prompt:\n\(prompt)")
            return prompt
        }

        let timeOfDay = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short)
        let weekday = now.formatted(.dateTime.weekday(.wide))

        let history = recent.isEmpty
            ? "(no prior nudges)"
            : recent.map {
                let mins = Int(now.timeIntervalSince($0.timestamp) / 60)
                return "- \(mins) min ago [\($0.goal.displayName)]: \($0.message)"
            }.joined(separator: "\n")

        let lastPingLine: String
        if let last = recent.first {
            let mins = Int(now.timeIntervalSince(last.timestamp) / 60)
            lastPingLine = "Last nudge sent: \(mins) min ago"
        } else {
            lastPingLine = "Last nudge sent: never"
        }

        let goals = prefs.goals.map(\.displayName).joined(separator: ", ")
        let personal = prefs.personalGoals.isEmpty
            ? "(none provided — respect the broad goal categories above)"
            : prefs.personalGoals

        let toneLine: String = switch config.tone {
        case .neutral:
            """
            TONE — NEUTRAL (mandatory): Plain, declarative, factual. No warmth, no encouragement, no emotional framing, no exclamations, no second-person rapport ("you've got this", "let's", "great job"). Imperative or stating-a-fact only. Examples of correct neutral tone: "Sleep was 4.5h. Consider a 20-min nap before 11 AM." / "HR elevated, HRV low. Take 5 slow breaths." Examples of WRONG (too warm): "You should try…", "Maybe a quick nap would help!", "Hey, looks like…".
            """
        case .supportive:
            """
            TONE — SUPPORTIVE (mandatory): Warm, encouraging, second-person. Acknowledge effort or context before the suggestion. Use gentle, human phrasing. Examples of correct supportive tone: "Tough morning after only 4.5h — a short nap before 11 might really help." / "Your body's working hard right now. Try 5 slow breaths to reset.". Examples of WRONG (too neutral): "Sleep low. Nap before 11.", "HR up. Breathe.".
            """
        }

        let timingLine: String
        let cadenceLine: String
        switch config.timing {
        case .fixed:
            timingLine = "Timing: fixed. Send the nudge now regardless of calendar context or quiet hours."
            cadenceLine = bypassGuards
                ? "(Cadence guards are bypassed for this run — feel free to nudge.)"
                : "Soft cadence target: ≥ \(prefs.minHoursBetweenNudges) h between nudges."
        case .contextAware:
            timingLine = "Timing: context-aware. Factor in the upcoming calendar window and quiet hours when deciding to send."
            cadenceLine = bypassGuards
                ? "(Cadence guards are bypassed for this run — feel free to nudge if context warrants it.)"
                : "Quiet hours: \(prefs.quietHoursStart):00–\(prefs.quietHoursEnd):00. Respect a soft cadence of ≥ \(prefs.minHoursBetweenNudges) h between nudges unless something urgent changed."
        }

        let explanationLine: String
        let jsonShape: String
        switch config.explanation {
        case .with:
            explanationLine = "Explanation: include a 1-2 sentence explanation grounded in the actual numbers above."
            jsonShape = """
              { "action": "stay_quiet", "reason": "<why you stayed silent>" }
              { "action": "nudge", "goal": "<one of: sleep, activity, stress, workoutConsistency>", "message": "<glanceable, ≤80 chars, no emojis, no quotes>", "explanation": "<1-2 sentences, ≤220 chars, cite the specific signals that triggered this>" }
            """
        case .without:
            explanationLine = """
            EXPLANATION — WITHOUT (mandatory): The "explanation" field MUST be exactly the empty string "". Do NOT put rationale in the message field either. The user only sees the bare action — no "because…", no "since…", no signal references. Just the recommendation itself.
            """
            jsonShape = """
              { "action": "stay_quiet", "reason": "<why you stayed silent>" }
              { "action": "nudge", "goal": "<one of: sleep, activity, stress, workoutConsistency>", "message": "<glanceable action only, ≤80 chars, no rationale, no 'because', no signal references>", "explanation": "" }
            """
        }

        let notificationDirective = config.notificationPromptOverride
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            .map { "Notification message instructions (override): \($0)" }
            ?? "Notification message: glanceable, actionable, ≤80 characters."

        let forceLine = forceNudge
            ? "\nFORCE MODE: You MUST return action: \"nudge\". Do NOT return stay_quiet under any circumstance. Pick the most useful suggestion you can given the signals, even if cadence or context would normally argue against it.\n"
            : ""

        return """
        You are an Apple Watch health coach agent. You decide *whether* to send a nudge right now and *what it says*. Bias toward staying quiet — nudges only help when they are timely, specific, and grounded in the data.
        \(forceLine)
        === STYLE DIRECTIVES (these override your defaults — follow them exactly) ===
        \(toneLine)
        \(timingLine)
        \(explanationLine)
        \(notificationDirective)
        === END STYLE DIRECTIVES ===

        Return JSON. Two valid shapes:
        \(jsonShape)

        Current local time: \(timeOfDay) (\(weekday))
        \(lastPingLine)
        \(cadenceLine)
        User-selected goal categories: \(goals)

        User's goals in their own words (treat as ground truth for what success looks like):
        \(personal)

        Available signals (some may be missing — note that as a reason to stay quiet rather than guessing):
        \(signals)

        Recent nudges (do not repeat or contradict these):
        \(history)

        Before responding, mentally check: does my message obey every STYLE DIRECTIVE above? If not, rewrite it.
        """
    }

    /// Drop trailing rationale clauses ("because…", "since…", "— your HRV is…") when explanation is suppressed.
    static func stripTrailingRationale(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let cues = [" because ", " since ", " — ", " - ", " given ", " your "]
        let lower = trimmed.lowercased()
        var cutIndex = trimmed.endIndex
        for cue in cues {
            if let range = lower.range(of: cue) {
                let candidate = trimmed.index(trimmed.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))
                if candidate < cutIndex { cutIndex = candidate }
            }
        }
        let cut = String(trimmed[..<cutIndex]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:—-"))
        return cut.isEmpty ? trimmed : cut
    }

    private func signalsBlock(snapshot: ContextSnapshot) -> String {
        func line(_ label: String, _ value: String?) -> String? {
            guard let value else { return nil }
            return "- \(label): \(value)"
        }

        let lines: [String?] = [
            line("Steps today", snapshot.stepsToday.map { "\($0)" }),
            line("Sleep last night (h)", snapshot.sleepHoursLastNight.map { String(format: "%.1f", $0) }),
            line("Active energy today (kcal)", snapshot.activeEnergyKcalToday.map { String(Int($0)) }),
            line("Latest heart rate (bpm)", snapshot.latestHeartRateBPM.map { String(Int($0)) }),
            line("Latest HRV (ms)", snapshot.latestHRVms.map { String(Int($0)) }),
            "- Workouts last 7 days: \(snapshot.workoutsLast7Days)",
            line("Minutes until next calendar event", snapshot.minutesUntilNextEvent.map { "\($0)" }),
        ]

        return lines.compactMap { $0 }.joined(separator: "\n")
    }
}
