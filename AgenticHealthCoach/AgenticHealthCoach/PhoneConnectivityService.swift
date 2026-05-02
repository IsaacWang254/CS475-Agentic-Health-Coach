//
//  PhoneConnectivityService.swift
//  AgenticHealthCoach
//

import Foundation
import SwiftData
import WatchConnectivity

final class PhoneConnectivityService: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivityService()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(_ payload: WatchPayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let userInfo: [String: Any] = [WatchPayload.userInfoKey: data]
        try? session.updateApplicationContext(userInfo)
        // Queued, guaranteed delivery — survives coalescing/dedup of applicationContext.
        session.transferUserInfo(userInfo)
    }

    /// Re-pushes the most recent recommendation so the watch reflects the phone's current state
    /// after relaunches, variant changes, or reinstalls.
    @MainActor
    func resendLatest(container: ModelContainer) {
        let context = container.mainContext

        var recDesc = FetchDescriptor<Recommendation>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        recDesc.fetchLimit = 1
        guard let rec = try? context.fetch(recDesc).first else { return }

        var snapDesc = FetchDescriptor<ContextSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        snapDesc.fetchLimit = 1
        let snapshot = try? context.fetch(snapDesc).first

        send(WatchPayload(
            recommendationID: rec.persistentModelID.storeIdentifier ?? UUID().uuidString,
            goalDisplayName: rec.goal.displayName,
            message: rec.message,
            explanation: rec.explanation,
            timestamp: rec.timestamp,
            stepsToday: snapshot?.stepsToday,
            sleepHoursLastNight: snapshot?.sleepHoursLastNight,
            minutesUntilNextEvent: snapshot?.minutesUntilNextEvent
        ))
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
