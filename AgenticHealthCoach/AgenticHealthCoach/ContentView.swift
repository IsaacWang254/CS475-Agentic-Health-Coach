//
//  ContentView.swift
//  AgenticHealthCoach
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferencesList: [UserPreferences]

    var body: some View {
        Group {
            if let prefs = preferencesList.first {
                if prefs.hasCompletedOnboarding {
                    MainTabs(preferences: prefs)
                } else {
                    OnboardingView(preferences: prefs) { /* state flips via @Query */ }
                }
            } else {
                ProgressView().task { ensurePreferences() }
            }
        }
    }

    private func ensurePreferences() {
        guard preferencesList.isEmpty else { return }
        modelContext.insert(UserPreferences())
        try? modelContext.save()
    }
}

private struct MainTabs: View {
    let preferences: UserPreferences

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Coach", systemImage: "sparkles") }
            ChatView()
                .tabItem { Label("Chat", systemImage: "text.bubble") }
            LabView()
                .tabItem { Label("Lab", systemImage: "flask") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            SettingsView(preferences: preferences)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [UserPreferences.self, ContextSnapshot.self, Recommendation.self, VariantPreset.self, ChatMessage.self], inMemory: true)
}
