//
//  HealthKitManager.swift
//  AgenticHealthCoach
//

import Foundation
import HealthKit

struct HealthAggregate {
    var stepsToday: Int?
    var sleepHoursLastNight: Double?
    var activeEnergyKcalToday: Double?
    var latestHeartRateBPM: Double?
    var latestHRVms: Double?
    var workoutsLast7Days: Int
}

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

    let store = HKHealthStore()
    private(set) var state: AuthorizationState = .notDetermined

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.stepCount),
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

    func currentAggregate() async -> HealthAggregate {
        async let steps = stepsToday()
        async let sleep = sleepHoursLastNight()
        async let energy = activeEnergyKcalToday()
        async let hr = latestQuantity(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrv = latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let workouts = workoutCountLast7Days()

        return await HealthAggregate(
            stepsToday: steps,
            sleepHoursLastNight: sleep,
            activeEnergyKcalToday: energy,
            latestHeartRateBPM: hr,
            latestHRVms: hrv,
            workoutsLast7Days: workouts
        )
    }

    private func stepsToday() async -> Int? {
        let type = HKQuantityType(.stepCount)
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let count = stats?.sumQuantity()?.doubleValue(for: .count())
                cont.resume(returning: count.map { Int($0) })
            }
            store.execute(query)
        }
    }

    private func sleepHoursLastNight() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal = Calendar.current
        let now = Date()
        let endOfMorning = cal.date(bySettingHour: 11, minute: 0, second: 0, of: now) ?? now
        let start = cal.date(byAdding: .hour, value: -24, to: endOfMorning) ?? now.addingTimeInterval(-86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: endOfMorning)

        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]
        let seconds = samples
            .filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return seconds > 0 ? seconds / 3600.0 : nil
    }

    private func activeEnergyKcalToday() async -> Double? {
        let type = HKQuantityType(.activeEnergyBurned)
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let kcal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie())
                cont.resume(returning: kcal)
            }
            store.execute(query)
        }
    }

    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let type = HKQuantityType(identifier)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]

        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: sort) { _, results, _ in
                let value = (results?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func workoutCountLast7Days() async -> Int {
        let start = Date().addingTimeInterval(-7 * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                cont.resume(returning: results?.count ?? 0)
            }
            store.execute(query)
        }
    }
}
