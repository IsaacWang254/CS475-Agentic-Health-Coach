//
//  LabView.swift
//  AgenticHealthCoach
//

import SwiftUI
import SwiftData

struct LabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var variants: [VariantPreset]

    @State private var scenario: ScenarioPreset = .s1PoorSleepBusyMorning
    @State private var useLiveSignals = false
    @State private var snapshotDraft = SnapshotDraft()
    @State private var simulatedNow: Date = .now
    @State private var customDraft = SnapshotDraft()
    @State private var customSimulatedNow: Date = .now

    @State private var variantChoice: VariantChoice = .a
    @State private var customConfig: PromptConfig = .presetA
    @State private var blockChoice: String = "1"
    @State private var customBlockTag: String = ""
    @State private var firing = false
    @State private var hasInitialized = false
    @State private var lastResult: String?
    @State private var lastError: String?
    @State private var toastMessage: String?

    enum VariantChoice: String, CaseIterable, Identifiable {
        case a, b, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .a: "A"; case .b: "B"; case .custom: "Custom"
            }
        }
    }

    private var activeConfig: PromptConfig {
        switch variantChoice {
        case .a: variants.first(where: { $0.name == "A" })?.config ?? .presetA
        case .b: variants.first(where: { $0.name == "B" })?.config ?? .presetB
        case .custom: customConfig
        }
    }

    private var activeVariantLabel: String {
        switch variantChoice { case .a: "A"; case .b: "B"; case .custom: "custom" }
    }

    private var resolvedBlockTag: String? {
        let raw = blockChoice == "custom" ? customBlockTag : blockChoice
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var selectedPresetName: String? {
        switch variantChoice {
        case .a: "A"
        case .b: "B"
        case .custom: nil
        }
    }

    private var activePresetBinding: Binding<PromptConfig> {
        Binding(
            get: { activeConfig },
            set: { updatePresetConfig($0) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scenario") {
                    Picker("Preset", selection: $scenario) {
                        ForEach(ScenarioPreset.allCases) { p in
                            Text(p.name).tag(p)
                        }
                    }
                    .onChange(of: scenario) { oldValue, newValue in
                        switchScenario(from: oldValue, to: newValue)
                    }

                    Text(scenario.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Use live signals (ignore preset)", isOn: $useLiveSignals)
                }

                if !useLiveSignals {
                    Section("Snapshot (editable)") {
                        SnapshotEditor(draft: $snapshotDraft, simulatedNow: $simulatedNow)
                        if scenario != .custom {
                            Button("Reset snapshot to \(scenario.name) defaults") {
                                let made = scenario.makeSnapshot()
                                snapshotDraft = SnapshotDraft(snapshot: made.snapshot)
                                simulatedNow = made.now
                            }
                        }
                    }
                }

                Section("Variant") {
                    Picker("Variant", selection: $variantChoice) {
                        ForEach(VariantChoice.allCases) { v in
                            Text(v.label).tag(v)
                        }
                    }
                    .pickerStyle(.segmented)

                    if variantChoice == .custom {
                        PromptConfigEditor(config: $customConfig)
                            .id("custom")
                    } else {
                        PromptConfigEditor(config: activePresetBinding)
                            .id(activeVariantLabel)
                        Button("Reset \(activeVariantLabel) to default") {
                            resetSelectedPreset()
                        }
                    }
                }

                Section("Block tag") {
                    Picker("Block", selection: $blockChoice) {
                        Text("1").tag("1")
                        Text("2").tag("2")
                        Text("3").tag("3")
                        Text("Custom").tag("custom")
                    }
                    .pickerStyle(.segmented)

                    if blockChoice == "custom" {
                        NoAssistantTextField(placeholder: "Custom block tag", text: $customBlockTag)
                            .frame(minHeight: 36)
                    }
                }

                if activeConfig.systemPromptOverride?.isEmpty == false {
                    Section {
                        OverrideBadge(text: "Raw system prompt override active")
                            .listRowInsets(EdgeInsets())
                    }
                }

                Section {
                    Button {
                        Task { await fire(force: false) }
                    } label: {
                        HStack {
                            if firing { ProgressView() }
                            Text(firing ? "Firing…" : "Fire")
                                .frame(maxWidth: .infinity)
                                .font(.headline)
                        }
                    }
                    .disabled(firing)

                    Button {
                        Task { await fire(force: true) }
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("Force Fire (ignore cadence & coach discretion)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                    }
                    .disabled(firing)
                }

                if let lastResult {
                    Section("Result") {
                        Text(lastResult).font(.callout)
                    }
                }
                if let lastError {
                    Section {
                        Text(lastError).font(.callout).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Lab")
            .onAppear {
                if !hasInitialized {
                    loadScenario(scenario)
                    hasInitialized = true
                }
                seedCustomFromActive()
            }
            .onChange(of: variantChoice) { _, _ in seedCustomFromActive() }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.red.opacity(0.9), in: .rect(cornerRadius: 10))
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func updatePresetConfig(_ config: PromptConfig) {
        guard let name = selectedPresetName else { return }
        if let preset = variants.first(where: { $0.name == name }) {
            preset.config = config
        } else {
            modelContext.insert(VariantPreset(name: name, config: config))
        }
        try? modelContext.save()
    }

    private func resetSelectedPreset() {
        guard let name = selectedPresetName else { return }
        updatePresetConfig(name == "B" ? .presetB : .presetA)
    }

    private func loadScenario(_ s: ScenarioPreset) {
        if s == .custom {
            snapshotDraft = customDraft
            simulatedNow = customSimulatedNow
        } else {
            let made = s.makeSnapshot()
            snapshotDraft = SnapshotDraft(snapshot: made.snapshot)
            simulatedNow = made.now
        }
        blockChoice = s.defaultBlockTag.isEmpty ? "custom" : s.defaultBlockTag
    }

    private func switchScenario(from old: ScenarioPreset, to new: ScenarioPreset) {
        if old == .custom {
            customDraft = snapshotDraft
            customSimulatedNow = simulatedNow
        }
        loadScenario(new)
    }

    private func seedCustomFromActive() {
        if variantChoice == .custom {
            // keep existing custom edits
            return
        }
        customConfig = activeConfig
    }

    private func fire(force: Bool) async {
        firing = true
        defer { firing = false }
        lastResult = nil
        lastError = nil

        let snapshot: ContextSnapshot
        let now: Date?
        guard let blockTag = resolvedBlockTag else {
            showError("Enter a custom block tag before firing.")
            return
        }

        if useLiveSignals {
            var descriptor = FetchDescriptor<ContextSnapshot>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            guard let live = try? modelContext.fetch(descriptor).first else {
                showError("No live snapshot available — pull to refresh on the Coach tab first.")
                return
            }
            snapshot = live
            now = nil
        } else {
            snapshot = snapshotDraft.toSnapshot(timestamp: simulatedNow)
            // Don't persist the synthetic snapshot — just pass it through.
            now = simulatedNow
        }

        let rec = await RecommendationEngine().runOnce(
            container: modelContext.container,
            snapshot: snapshot,
            config: activeConfig,
            simulatedNow: now,
            bypassGuards: true,
            variantLabel: activeVariantLabel,
            blockTag: blockTag,
            forceNudge: force
        )

        if let rec {
            var parts = ["Nudge: \(rec.message)"]
            if !rec.explanation.isEmpty {
                parts.append("Why: \(rec.explanation)")
            }
            parts.append("Fired with:\n\(snapshot.labSummary)")
            lastResult = parts.joined(separator: "\n\n")
        } else {
            showError("Coach chose to stay quiet (or the model returned no nudge).")
        }
    }

    private func showError(_ message: String) {
        lastError = message
        withAnimation {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                withAnimation {
                    if toastMessage == message {
                        toastMessage = nil
                    }
                }
            }
        }
    }
}

struct SnapshotDraft {
    var stepsToday: Int? = nil
    var sleepHoursLastNight: Double? = nil
    var activeEnergyKcalToday: Double? = nil
    var latestHeartRateBPM: Double? = nil
    var latestHRVms: Double? = nil
    var workoutsLast7Days: Int = 0
    var minutesUntilNextEvent: Int? = nil

    init() {}

    init(snapshot: ContextSnapshot) {
        self.stepsToday = snapshot.stepsToday
        self.sleepHoursLastNight = snapshot.sleepHoursLastNight
        self.activeEnergyKcalToday = snapshot.activeEnergyKcalToday
        self.latestHeartRateBPM = snapshot.latestHeartRateBPM
        self.latestHRVms = snapshot.latestHRVms
        self.workoutsLast7Days = snapshot.workoutsLast7Days
        self.minutesUntilNextEvent = snapshot.minutesUntilNextEvent
    }

    func toSnapshot(timestamp: Date) -> ContextSnapshot {
        ContextSnapshot(
            timestamp: timestamp,
            stepsToday: stepsToday,
            sleepHoursLastNight: sleepHoursLastNight,
            activeEnergyKcalToday: activeEnergyKcalToday,
            latestHeartRateBPM: latestHeartRateBPM,
            latestHRVms: latestHRVms,
            workoutsLast7Days: workoutsLast7Days,
            nextEventStart: minutesUntilNextEvent.map { timestamp.addingTimeInterval(TimeInterval($0 * 60)) },
            minutesUntilNextEvent: minutesUntilNextEvent
        )
    }
}

private extension ContextSnapshot {
    var labSummary: String {
        var lines: [String] = []
        if let stepsToday { lines.append("Steps: \(stepsToday)") }
        if let sleepHoursLastNight { lines.append("Sleep: \(String(format: "%.1f", sleepHoursLastNight)) h") }
        if let activeEnergyKcalToday { lines.append("Active energy: \(Int(activeEnergyKcalToday)) kcal") }
        if let latestHeartRateBPM { lines.append("Heart rate: \(Int(latestHeartRateBPM)) bpm") }
        if let latestHRVms { lines.append("HRV: \(Int(latestHRVms)) ms") }
        lines.append("Workouts 7d: \(workoutsLast7Days)")
        if let minutesUntilNextEvent {
            lines.append("Next event: \(minutesUntilNextEvent) min")
        } else {
            lines.append("Next event: none")
        }
        return lines.joined(separator: "\n")
    }
}

private struct SnapshotEditor: View {
    @Binding var draft: SnapshotDraft
    @Binding var simulatedNow: Date

    var body: some View {
        DatePicker("Simulated now", selection: $simulatedNow)
        OptionalIntField(label: "Steps today", value: $draft.stepsToday)
        OptionalDoubleField(label: "Sleep last night (h)", value: $draft.sleepHoursLastNight)
        OptionalDoubleField(label: "Active energy (kcal)", value: $draft.activeEnergyKcalToday)
        OptionalDoubleField(label: "Heart rate (bpm)", value: $draft.latestHeartRateBPM)
        OptionalDoubleField(label: "HRV (ms)", value: $draft.latestHRVms)
        Stepper("Workouts last 7d: \(draft.workoutsLast7Days)", value: $draft.workoutsLast7Days, in: 0...14)
        NextEventEditor(minutesUntilNextEvent: $draft.minutesUntilNextEvent)
    }
}

private struct NextEventEditor: View {
    @Binding var minutesUntilNextEvent: Int?
    @State private var hasNoUpcomingEvent = false

    var body: some View {
        Toggle("No upcoming event", isOn: $hasNoUpcomingEvent)
            .onAppear {
                hasNoUpcomingEvent = minutesUntilNextEvent == nil
            }
            .onChange(of: hasNoUpcomingEvent) { _, noEvent in
                if noEvent {
                    minutesUntilNextEvent = nil
                } else if minutesUntilNextEvent == nil {
                    minutesUntilNextEvent = 30
                }
            }
            .onChange(of: minutesUntilNextEvent) { _, newValue in
                hasNoUpcomingEvent = newValue == nil
            }

        if !hasNoUpcomingEvent {
            OptionalIntField(label: "Minutes until next event", value: $minutesUntilNextEvent)
        }
    }
}

private struct OptionalIntField: View {
    let label: String
    @Binding var value: Int?
    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .frame(width: 100)
                .onAppear { syncFromValue() }
                .onChange(of: value) { _, _ in syncFromValue() }
                .onChange(of: text) { _, new in
                    let parsed = Int(new)
                    if parsed != value { value = parsed }
                }
        }
    }

    private func syncFromValue() {
        let expected = value.map { String($0) } ?? ""
        if expected != text { text = expected }
    }
}

private struct OptionalDoubleField: View {
    let label: String
    @Binding var value: Double?
    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 100)
                .onAppear { syncFromValue() }
                .onChange(of: value) { _, _ in syncFromValue() }
                .onChange(of: text) { _, new in
                    let parsed = Double(new)
                    if parsed != value { value = parsed }
                }
        }
    }

    private func syncFromValue() {
        let expected = value.map { String($0) } ?? ""
        if expected != text { text = expected }
    }
}

private struct PromptConfigEditor: View {
    @Binding var config: PromptConfig
    @State private var systemOverride: String = ""
    @State private var notificationOverride: String = ""

    var body: some View {
        Picker("Tone", selection: $config.tone) {
            ForEach(PromptTone.allCases) { Text($0.displayName).tag($0) }
        }
        Picker("Timing", selection: $config.timing) {
            ForEach(PromptTiming.allCases) { Text($0.displayName).tag($0) }
        }
        Picker("Explanation", selection: $config.explanation) {
            ForEach(PromptExplanation.allCases) { Text($0.displayName).tag($0) }
        }

        VStack(alignment: .leading) {
            Text("System prompt override").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $systemOverride)
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                .onAppear { systemOverride = config.systemPromptOverride ?? "" }
                .onChange(of: config.systemPromptOverride) { _, new in
                    let incoming = new ?? ""
                    if incoming != systemOverride { systemOverride = incoming }
                }
                .onChange(of: systemOverride) { _, new in
                    let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                    let next: String? = trimmed.isEmpty ? nil : new
                    if next != config.systemPromptOverride { config.systemPromptOverride = next }
                }
        }

        VStack(alignment: .leading) {
            Text("Notification message instructions override").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $notificationOverride)
                .frame(minHeight: 50)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                .onAppear { notificationOverride = config.notificationPromptOverride ?? "" }
                .onChange(of: config.notificationPromptOverride) { _, new in
                    let incoming = new ?? ""
                    if incoming != notificationOverride { notificationOverride = incoming }
                }
                .onChange(of: notificationOverride) { _, new in
                    let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                    let next: String? = trimmed.isEmpty ? nil : new
                    if next != config.notificationPromptOverride { config.notificationPromptOverride = next }
                }
        }
    }
}

private struct ConfigSummary: View {
    let config: PromptConfig
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tone: \(config.tone.displayName)").font(.caption)
            Text("Timing: \(config.timing.displayName)").font(.caption)
            Text("Explanation: \(config.explanation.displayName)").font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}

struct NoAssistantTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.borderStyle = .none
        field.placeholder = placeholder
        field.autocorrectionType = .no
        field.autocapitalizationType = .allCharacters
        field.returnKeyType = .done
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textChanged(_ sender: UITextField) {
            text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
