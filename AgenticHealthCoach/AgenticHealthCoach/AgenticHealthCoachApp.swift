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
                    await ContextSyncService.syncNow(container: sharedModelContainer)
                    ContextSyncService.scheduleNextRefresh()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
