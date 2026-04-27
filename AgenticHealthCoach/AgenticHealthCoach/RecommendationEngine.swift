//
//  RecommendationEngine.swift
//  AgenticHealthCoach
//

import Foundation
import SwiftData

@MainActor
struct RecommendationEngine {
    var client: GeminiClient = GeminiClient()

    func runOnce(container: ModelContainer) async {
        let context = container.mainContext

        let prefs = currentPreferences(context: context)
        guard let snapshot = latestSnapshot(context: context) else { return }
        let recent = recentRecommendations(context: context, limit: 5)

        let prompt = buildPrompt(snapshot: snapshot, prefs: prefs, recent: recent)

        let decision: AgentDecision
        do {
            decision = try await client.decide(prompt: prompt)
        } catch {
            return
        }

        guard
            decision.action == .nudge,
            let message = decision.message?.trimmingCharacters(in: .whitespacesAndNewlines),
            !message.isEmpty
        else { return }

        let goal = HealthGoal(rawValue: decision.goal ?? "") ?? prefs.goals.first ?? .activity
        let rec = Recommendation(
            timestamp: .now,
            goal: goal,
            message: message,
            explanation: decision.explanation ?? ""
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

    private func buildPrompt(
        snapshot: ContextSnapshot,
        prefs: UserPreferences,
        recent: [Recommendation]
    ) -> String {
        let now = Date.now
        let timeOfDay = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short)
        let weekday = now.formatted(.dateTime.weekday(.wide))

        let signals = signalsBlock(snapshot: snapshot)
        let history = recent.isEmpty
            ? "(no prior nudges)"
            : recent.map {
                let mins = Int(now.timeIntervalSince($0.timestamp) / 60)
                return "- \(mins) min ago [\($0.goal.displayName)]: \($0.message)"
            }.joined(separator: "\n")

        let goals = prefs.goals.map(\.displayName).joined(separator: ", ")

        return """
        You are an Apple Watch health coach agent. You decide *whether* to send a nudge right now and *what it says*. Bias toward staying quiet — nudges only help when they are timely, specific, and grounded in the data.

        Return JSON. Two valid shapes:
          { "action": "stay_quiet", "reason": "<why you stayed silent>" }
          { "action": "nudge", "goal": "<one of: sleep, activity, stress, workoutConsistency>", "message": "<glanceable, ≤80 chars, no emojis, no quotes>", "explanation": "<1-2 sentences, ≤220 chars, cite the specific signals that triggered this>" }

        Current local time: \(timeOfDay) (\(weekday))
        Quiet hours: \(prefs.quietHoursStart):00–\(prefs.quietHoursEnd):00 (avoid nudging in this window unless urgent)
        User-selected goals: \(goals)
        Tone: \(prefs.tone.rawValue)

        Available signals (some may be missing — note that as a reason to stay quiet rather than guessing):
        \(signals)

        Recent nudges (do not repeat or contradict these; respect a soft cadence — the user prefers ≥ \(prefs.minHoursBetweenNudges) hours between nudges unless something urgent changed):
        \(history)

        Decide now. If you nudge, ground the explanation in the actual numbers above.
        """
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
