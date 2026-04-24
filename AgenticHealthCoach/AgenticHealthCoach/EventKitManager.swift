//
//  EventKitManager.swift
//  AgenticHealthCoach
//

import Foundation
import EventKit

@Observable
final class EventKitManager {
    enum AuthorizationState {
        case notDetermined
        case requesting
        case authorized
        case denied
        case restricted
        case failed(Error)
    }

    static let shared = EventKitManager()

    let store = EKEventStore()
    private(set) var state: AuthorizationState = .notDetermined

    func requestAuthorization() async {
        state = .requesting
        do {
            let granted = try await store.requestFullAccessToEvents()
            state = granted ? .authorized : .denied
        } catch {
            state = .failed(error)
        }
    }
}
