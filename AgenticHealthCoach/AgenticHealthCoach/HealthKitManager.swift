//
//  HealthKitManager.swift
//  AgenticHealthCoach
//

import Foundation
import HealthKit

@Observable
final class HealthKitManager {
    enum AuthorizationState {
        case notDetermined
        case requesting
        case authorized
        case denied
        case unavailable
        case failed(Error)
    }

    static let shared = HealthKitManager()

    private let store = HKHealthStore()
    private(set) var state: AuthorizationState = .notDetermined

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
        ]
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }

        state = .requesting
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            state = .authorized
        } catch {
            state = .failed(error)
        }
    }
}
