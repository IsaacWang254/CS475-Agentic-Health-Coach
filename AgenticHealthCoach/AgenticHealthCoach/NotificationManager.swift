//
//  NotificationManager.swift
//  AgenticHealthCoach
//

import Foundation
import UserNotifications

@Observable
final class NotificationManager {
    enum AuthorizationState {
        case notDetermined
        case requesting
        case authorized
        case denied
        case failed(Error)
    }

    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private(set) var state: AuthorizationState = .notDetermined

    func requestAuthorization() async {
        state = .requesting
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            state = granted ? .authorized : .denied
        } catch {
            state = .failed(error)
        }
    }
}
