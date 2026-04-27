//
//  WatchConnectivityService.swift
//  AgenticHealthCoach Watch Watch App
//

import Foundation
import WatchConnectivity

@Observable
final class WatchConnectivityService: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityService()

    private(set) var latest: WatchPayload?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        loadPersistedPayload()
        if let data = session.receivedApplicationContext[WatchPayload.userInfoKey] as? Data {
            decode(data)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        guard let data = applicationContext[WatchPayload.userInfoKey] as? Data else { return }
        decode(data)
    }

    private func decode(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(WatchPayload.self, from: data) else { return }
        Task { @MainActor in
            self.latest = payload
            self.persist(data)
        }
    }

    private var cacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("latestPayload.json")
    }

    private func persist(_ data: Data) {
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func loadPersistedPayload() {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder().decode(WatchPayload.self, from: data) else { return }
        latest = payload
    }
}
