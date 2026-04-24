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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await HealthKitManager.shared.requestAuthorization()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
