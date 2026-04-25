//
//  AgenticHealthCoachApp.swift
//  AgenticHealthCoach
//
//  Created by Aimdrone 254 on 4/24/26.
//

import SwiftUI
import SwiftData

@main
struct AgenticHealthCoachApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            UserPreferences.self,
            ContextSnapshot.self,
            Recommendation.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        ContextSyncService.registerBackgroundTasks(container: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await HealthKitManager.shared.requestAuthorization()
                    await EventKitManager.shared.requestAuthorization()
                    await NotificationManager.shared.requestAuthorization()
                    await ContextSyncService.syncNow(container: sharedModelContainer)
                    ContextSyncService.scheduleNextRefresh()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
