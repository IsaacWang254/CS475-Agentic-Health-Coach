//
//  NotificationManager.swift
//  AgenticHealthCoach
//

import Foundation
import UserNotifications
import SwiftData

@Observable
final class NotificationManager: NSObject {
    enum AuthorizationState {
        case notDetermined
        case requesting
        case authorized
        case denied
        case failed(Error)
    }

    static let shared = NotificationManager()

    static let categoryID = "AGENT_NUDGE"
    static let actAction = "AGENT_ACT"
    static let snoozeAction = "AGENT_SNOOZE"
    static let dismissAction = "AGENT_DISMISS"
    static let recommendationIDKey = "recommendationID"

    private let center = UNUserNotificationCenter.current()
    private(set) var state: AuthorizationState = .notDetermined

    var modelContainer: ModelContainer?

    func configure() {
        center.delegate = self

        let act = UNNotificationAction(
            identifier: Self.actAction,
            title: "Acted on it",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeAction,
            title: "Snooze 1h",
            options: []
        )
        let dismiss = UNNotificationAction(
            identifier: Self.dismissAction,
            title: "Dismiss",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [act, snooze, dismiss],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async {
        state = .requesting
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            state = granted ? .authorized : .denied
        } catch {
            state = .failed(error)
        }
    }

    func schedule(for recommendation: Recommendation) {
        guard case .authorized = state else { return }

        let content = UNMutableNotificationContent()
        content.title = recommendation.goal.displayName
        content.body = recommendation.message
        content.subtitle = recommendation.explanation
        content.categoryIdentifier = Self.categoryID
        content.sound = .default
        content.userInfo = [Self.recommendationIDKey: recommendation.persistentModelID.storeIdentifier ?? ""]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { _ in }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo
        guard
            let storeID = userInfo[Self.recommendationIDKey] as? String,
            !storeID.isEmpty,
            let container = modelContainer
        else { return }

        Task { @MainActor in
            let context = container.mainContext
            guard
                let all = try? context.fetch(FetchDescriptor<Recommendation>()),
                let rec = all.first(where: { $0.persistentModelID.storeIdentifier == storeID })
            else { return }

            switch response.actionIdentifier {
            case Self.actAction:
                rec.actedOn = true
            case Self.dismissAction:
                rec.dismissed = true
            case Self.snoozeAction:
                rec.dismissed = true
                // Soft snooze: bump the timestamp forward so cadence respects it.
                rec.timestamp = Date.now.addingTimeInterval(3600)
            default:
                break
            }
            try? context.save()
        }
    }
}
