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
        refreshAuthorizationState()
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
        let title = recommendation.goal.displayName
        let subtitle: String
        let body: String
        if recommendation.explanation.isEmpty {
            body = recommendation.message
            subtitle = ""
        } else {
            body = "\(recommendation.message)\n\(recommendation.explanation)"
            subtitle = "Why this nudge"
        }
        let recommendationID = recommendation.persistentModelID.storeIdentifier ?? ""

        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.updateAuthorizationState(.authorized)
                self.enqueueNotification(
                    title: title,
                    subtitle: subtitle,
                    body: body,
                    recommendationID: recommendationID
                )
            case .notDetermined:
                self.updateAuthorizationState(.requesting)
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        self.updateAuthorizationState(.failed(error))
                        print("Notification authorization failed: \(error.localizedDescription)")
                        return
                    }

                    guard granted else {
                        self.updateAuthorizationState(.denied)
                        print("Notification authorization denied; skipping nudge notification.")
                        return
                    }

                    self.updateAuthorizationState(.authorized)
                    self.enqueueNotification(
                        title: title,
                        subtitle: subtitle,
                        body: body,
                        recommendationID: recommendationID
                    )
                }
            case .denied:
                self.updateAuthorizationState(.denied)
                print("Notifications are denied in iOS Settings; skipping nudge notification.")
            @unknown default:
                self.updateAuthorizationState(.denied)
                print("Unknown notification authorization status; skipping nudge notification.")
            }
        }
    }

    private func enqueueNotification(title: String, subtitle: String, body: String, recommendationID: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.categoryIdentifier = Self.categoryID
        content.sound = .default
        content.userInfo = [Self.recommendationIDKey: recommendationID]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                print("Failed to schedule nudge notification: \(error.localizedDescription)")
            } else {
                print("Scheduled nudge notification.")
            }
        }
    }

    private func refreshAuthorizationState() {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.updateAuthorizationState(.authorized)
            case .denied:
                self.updateAuthorizationState(.denied)
            case .notDetermined:
                self.updateAuthorizationState(.notDetermined)
            @unknown default:
                self.updateAuthorizationState(.denied)
            }
        }
    }

    private func updateAuthorizationState(_ newState: AuthorizationState) {
        DispatchQueue.main.async {
            self.state = newState
        }
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
