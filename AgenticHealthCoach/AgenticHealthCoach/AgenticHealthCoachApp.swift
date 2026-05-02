//
//  AgenticHealthCoachApp.swift
//  AgenticHealthCoach
//
//  Created by Aimdrone 254 on 4/24/26.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct AgenticHealthCoachApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserPreferences.self,
            ContextSnapshot.self,
            Recommendation.self,
            VariantPreset.self,
            ChatMessage.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        FirebaseApp.configure()
        ContextSyncService.registerBackgroundTasks(container: sharedModelContainer)
        NotificationManager.shared.modelContainer = sharedModelContainer
        NotificationManager.shared.configure()
        PhoneConnectivityService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    seedVariantPresetsIfNeeded()
                    await ContextSyncService.syncNow(container: sharedModelContainer)
                    ContextSyncService.scheduleNextRefresh()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    @MainActor
    private func seedVariantPresetsIfNeeded() {
        let context = sharedModelContainer.mainContext
        let existing = (try? context.fetch(FetchDescriptor<VariantPreset>())) ?? []
        let names = Set(existing.map(\.name))
        if !names.contains("A") {
            context.insert(VariantPreset(name: "A", config: .presetA))
        }
        if !names.contains("B") {
            context.insert(VariantPreset(name: "B", config: .presetB))
        }
        try? context.save()
    }
}
