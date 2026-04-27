//
//  OnboardingView.swift
//  AgenticHealthCoach
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let preferences: UserPreferences
    var onFinish: () -> Void

    @State private var selectedGoals: Set<HealthGoal> = []
    @State private var tone: AgentTone = .empathetic
    @State private var requesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Welcome to your Agentic Health Coach.")
                        .font(.title2.bold())
                    Text("Pick the areas you want help with. The agent will use your watch and calendar signals to nudge you only when it can be useful.")
                        .foregroundStyle(.secondary)
                }

                Section("Your goals") {
                    ForEach(HealthGoal.allCases) { goal in
                        Toggle(goal.displayName, isOn: Binding(
                            get: { selectedGoals.contains(goal) },
                            set: { isOn in
                                if isOn { selectedGoals.insert(goal) } else { selectedGoals.remove(goal) }
                            }
                        ))
                    }
                }

                Section("Tone") {
                    Picker("Coach tone", selection: $tone) {
                        ForEach(AgentTone.allCases) { tone in
                            Text(tone.rawValue.capitalized).tag(tone)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        Task { await finish() }
                    } label: {
                        HStack {
                            Spacer()
                            if requesting { ProgressView() } else { Text("Grant access & continue").bold() }
                            Spacer()
                        }
                    }
                    .disabled(selectedGoals.isEmpty || requesting)
                } footer: {
                    Text("We'll request HealthKit, Calendar, and Notification permissions next. You can change these anytime in Settings.")
                }
            }
            .navigationTitle("Get started")
            .onAppear {
                selectedGoals = Set(preferences.goals)
                tone = preferences.tone
            }
        }
    }

    private func finish() async {
        requesting = true
        defer { requesting = false }

        preferences.goals = Array(selectedGoals)
        preferences.tone = tone
        preferences.hasCompletedOnboarding = true
        try? modelContext.save()

        await HealthKitManager.shared.requestAuthorization()
        await EventKitManager.shared.requestAuthorization()
        await NotificationManager.shared.requestAuthorization()

        onFinish()
    }
}
