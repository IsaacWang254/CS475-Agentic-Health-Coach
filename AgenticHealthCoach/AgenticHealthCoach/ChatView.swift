//
//  ChatView.swift
//  AgenticHealthCoach
//

import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.timestamp, order: .forward) private var messages: [ChatMessage]
    @Query(sort: \ContextSnapshot.timestamp, order: .reverse) private var snapshots: [ContextSnapshot]
    @Query private var preferencesList: [UserPreferences]
    @Query private var variants: [VariantPreset]

    @State private var input: String = ""
    @State private var sending = false
    @State private var errorText: String?
    @State private var retryText: String?
    @State private var retryVariant: String?
    @State private var selectedVariant: String = "A"

    private var activeConfig: PromptConfig {
        config(for: selectedVariant)
    }

    private func config(for variant: String) -> PromptConfig {
        if let v = variants.first(where: { $0.name == variant }) {
            return v.config
        }
        return variant == "B" ? .presetB : .presetA
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if activeConfig.systemPromptOverride?.isEmpty == false {
                    OverrideBadge(text: "Raw system prompt override active")
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if messages.isEmpty {
                                ContentUnavailableView(
                                    "Ask the coach",
                                    systemImage: "text.bubble",
                                    description: Text("Type a question — the coach will use your latest signals as context.")
                                )
                                .padding(.top, 40)
                            }
                            ForEach(messages) { msg in
                                ChatBubble(message: msg).id(msg.persistentModelID)
                            }
                            if let errorText {
                                HStack {
                                    Text(errorText)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                    Spacer()
                                    if retryText != nil {
                                        Button("Retry") {
                                            Task { await retryLastFailedMessage() }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(sending)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.persistentModelID, anchor: .bottom) }
                        }
                    }
                }

                Divider()

                HStack(alignment: .bottom) {
                    Picker("Variant", selection: $selectedVariant) {
                        Text("A").tag("A")
                        Text("B").tag("B")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)

                    TextField("Ask the coach…", text: $input, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .disabled(sending)

                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: sending ? "ellipsis.circle" : "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(sending || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Chat")
        }
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        await submit(text: text, variant: selectedVariant, insertUserMessage: true)
    }

    private func retryLastFailedMessage() async {
        guard let text = retryText else { return }
        input = ""
        await submit(text: text, variant: retryVariant ?? selectedVariant, insertUserMessage: false)
    }

    private func submit(text: String, variant: String, insertUserMessage: Bool) async {
        errorText = nil

        if insertUserMessage {
            let userMsg = ChatMessage(role: "user", text: text, variantLabel: variant)
            modelContext.insert(userMsg)
            try? modelContext.save()
        }

        sending = true
        defer { sending = false }

        let prompt = buildChatPrompt(userMessage: text, config: config(for: variant))
        do {
            let reply = try await GeminiClient().reply(prompt: prompt)
            let assistant = ChatMessage(role: "assistant", text: reply, variantLabel: variant)
            modelContext.insert(assistant)
            try? modelContext.save()
            retryText = nil
            retryVariant = nil
        } catch {
            errorText = "Couldn't reach the coach."
            retryText = text
            retryVariant = variant
            input = text
        }
    }

    private func buildChatPrompt(userMessage: String, config: PromptConfig) -> String {
        let snapshot = snapshots.first
        let prefs = preferencesList.first ?? UserPreferences()

        let signals = snapshot.map { snap -> String in
            var lines: [String] = []
            if let s = snap.stepsToday { lines.append("- Steps today: \(s)") }
            if let s = snap.sleepHoursLastNight { lines.append("- Sleep last night (h): \(String(format: "%.1f", s))") }
            if let s = snap.activeEnergyKcalToday { lines.append("- Active energy today (kcal): \(Int(s))") }
            if let s = snap.latestHeartRateBPM { lines.append("- Latest heart rate (bpm): \(Int(s))") }
            if let s = snap.latestHRVms { lines.append("- Latest HRV (ms): \(Int(s))") }
            lines.append("- Workouts last 7 days: \(snap.workoutsLast7Days)")
            if let m = snap.minutesUntilNextEvent { lines.append("- Minutes until next calendar event: \(m)") }
            return lines.joined(separator: "\n")
        } ?? "(no recent signals available)"

        let history = messages.suffix(10).map { "\($0.role.capitalized): \($0.text)" }.joined(separator: "\n")

        if let override = config.systemPromptOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let prompt = """
            \(override)

            Available signals:
            \(signals)

            Conversation so far:
            \(history)

            User: \(userMessage)
            Assistant:
            """
            print("DEV outgoing chat override prompt:\n\(prompt)")
            return prompt
        }

        let toneLine = config.tone == .neutral
            ? "Reply in a neutral, matter-of-fact tone."
            : "Reply in a supportive, encouraging tone."
        let explanationLine = config.explanation == .with
            ? "When you give advice, briefly cite the specific signals that motivated it."
            : "Give the advice directly without justification."

        let personal = prefs.personalGoals.isEmpty ? "(none provided)" : prefs.personalGoals

        return """
        You are an Apple Watch health coach having a short conversation with the user. Keep replies concise (2-4 sentences) and grounded in the signals below.

        \(toneLine)
        \(explanationLine)

        User's stated goals: \(personal)

        Available signals:
        \(signals)

        Conversation so far:
        \(history)

        User: \(userMessage)
        Assistant:
        """
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 40) }
            Text(message.text)
                .padding(10)
                .background(message.role == "user" ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15),
                            in: .rect(cornerRadius: 12))
            if message.role != "user" { Spacer(minLength: 40) }
        }
    }
}

struct OverrideBadge: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.caption.bold())
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.25))
        .foregroundStyle(.orange)
    }
}
