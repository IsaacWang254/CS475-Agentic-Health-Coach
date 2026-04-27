//
//  PhoneConnectivityService.swift
//  AgenticHealthCoach
//

import Foundation
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
        do {
            let data = try JSONEncoder().encode(payload)
            try session.updateApplicationContext([WatchPayload.userInfoKey: data])
        } catch {
            // Best-effort; the watch will get the next payload.
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
