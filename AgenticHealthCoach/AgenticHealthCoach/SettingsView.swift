//
//  SettingsView.swift
//  AgenticHealthCoach
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let preferences: UserPreferences

    @State private var goals: Set<HealthGoal> = []
    @State private var personalGoals: String = ""
    @State private var tone: AgentTone = .empathetic
    @State private var minHours: Int = 3
    @State private var quietStart: Int = 22
    @State private var quietEnd: Int = 7

    var body: some View {
        NavigationStack {
            Form {
                Section("Goals") {
                    ForEach(HealthGoal.allCases) { goal in
                        Toggle(goal.displayName, isOn: Binding(
                            get: { goals.contains(goal) },
                            set: { isOn in
                                if isOn { goals.insert(goal) } else { goals.remove(goal) }
                                save()
                            }
                        ))
                    }
                }

                Section {
                    TextField(
                        "e.g. Walk 8k steps daily. In bed by 11pm.",
                        text: $personalGoals,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .onChange(of: personalGoals) { save() }
                } header: {
                    Text("Your goals in your words")
                } footer: {
                    Text("The agent reads these every time it decides whether to nudge you.")
                }

                Section {
                    Picker("Coach tone", selection: $tone) {
                        ForEach(AgentTone.allCases) { tone in
                            Text(tone.rawValue.capitalized).tag(tone)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: tone) { save() }
                } header: {
                    Text("Persona")
                } footer: {
                    Text("Affects how the agent words its nudges.")
                }

                Section {
                    Stepper("Min hours between nudges: \(minHours)", value: $minHours, in: 1...12)
                        .onChange(of: minHours) { save() }
                    Stepper("Quiet hours start: \(formatHour(quietStart))", value: $quietStart, in: 0...23)
                        .onChange(of: quietStart) { save() }
                    Stepper("Quiet hours end: \(formatHour(quietEnd))", value: $quietEnd, in: 0...23)
                        .onChange(of: quietEnd) { save() }
                } header: {
                    Text("Frequency")
                } footer: {
                    Text("These are soft signals to the agent. It may still surface urgent nudges.")
                }

                Section("System access") {
                    PermissionRow(label: "Health data", state: healthState)
                    PermissionRow(label: "Calendar", state: calendarState)
                    PermissionRow(label: "Notifications", state: notificationState)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear { load() }
        }
    }

    private func load() {
        goals = Set(preferences.goals)
        personalGoals = preferences.personalGoals
        tone = preferences.tone
        minHours = preferences.minHoursBetweenNudges
        quietStart = preferences.quietHoursStart
        quietEnd = preferences.quietHoursEnd
    }

    private func save() {
        preferences.goals = Array(goals)
        preferences.personalGoals = personalGoals.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.tone = tone
        preferences.minHoursBetweenNudges = minHours
        preferences.quietHoursStart = quietStart
        preferences.quietHoursEnd = quietEnd
        try? modelContext.save()
    }

    private func formatHour(_ hour: Int) -> String {
        let suffix = hour < 12 ? "AM" : "PM"
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(suffix)"
    }

    private var healthState: String {
        switch HealthKitManager.shared.state {
        case .authorized: "Granted"
        case .denied: "Denied"
        case .unavailable: "Unavailable"
        case .requesting: "Requesting…"
        case .notDetermined: "Not requested"
        case .failed: "Error"
        }
    }
    private var calendarState: String {
        switch EventKitManager.shared.state {
        case .authorized: "Granted"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .requesting: "Requesting…"
        case .notDetermined: "Not requested"
        case .failed: "Error"
        }
    }
    private var notificationState: String {
        switch NotificationManager.shared.state {
        case .authorized: "Granted"
        case .denied: "Denied"
        case .requesting: "Requesting…"
        case .notDetermined: "Not requested"
        case .failed: "Error"
        }
    }
}

private struct PermissionRow: View {
    let label: String
    let state: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(state).foregroundStyle(.secondary)
        }
    }
}
