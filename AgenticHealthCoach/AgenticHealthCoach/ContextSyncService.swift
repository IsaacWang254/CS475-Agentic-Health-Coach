//
//  ContextSyncService.swift
//  AgenticHealthCoach
//

import Foundation
import BackgroundTasks
import SwiftData

enum ContextSyncService {
    static let refreshTaskID = "edu.purdue.AgenticHealthCoach.contextRefresh"
    static let minRefreshInterval: TimeInterval = 30 * 60

    static func registerBackgroundTasks(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            handle(task: task as! BGAppRefreshTask, container: container)
        }
    }

    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minRefreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Submission can fail in the simulator or when the app is foregrounded.
        }
    }

    @MainActor
    static func syncNow(container: ModelContainer) async {
        let health = await HealthKitManager.shared.currentAggregate()
        let cal = EventKitManager.shared.currentContext()

        let snapshot = ContextSnapshot(
            timestamp: .now,
            sleepHoursLastNight: health.sleepHoursLastNight,
            activeEnergyKcalToday: health.activeEnergyKcalToday,
            latestHeartRateBPM: health.latestHeartRateBPM,
            latestHRVms: health.latestHRVms,
            workoutsLast7Days: health.workoutsLast7Days,
            nextEventStart: cal.nextEventStart,
            minutesUntilNextEvent: cal.minutesUntilNextEvent
        )

        let context = container.mainContext
        context.insert(snapshot)
        pruneSnapshots(context: context, keepLast: 200)
        try? context.save()
    }

    private static func handle(task: BGAppRefreshTask, container: ModelContainer) {
        scheduleNextRefresh()

        let work = Task { @MainActor in
            await syncNow(container: container)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    @MainActor
    private static func pruneSnapshots(context: ModelContext, keepLast: Int) {
        let descriptor = FetchDescriptor<ContextSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > keepLast else { return }
        for snap in all.dropFirst(keepLast) {
            context.delete(snap)
        }
    }
}
