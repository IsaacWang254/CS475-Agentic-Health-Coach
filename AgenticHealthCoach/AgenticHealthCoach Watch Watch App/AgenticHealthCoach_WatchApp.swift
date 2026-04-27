//
//  AgenticHealthCoach_WatchApp.swift
//  AgenticHealthCoach Watch Watch App
//

import SwiftUI

@main
struct AgenticHealthCoach_Watch_Watch_AppApp: App {
    init() {
        WatchConnectivityService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
