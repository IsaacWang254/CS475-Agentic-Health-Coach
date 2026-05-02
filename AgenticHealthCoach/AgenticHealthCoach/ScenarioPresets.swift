//
//  ScenarioPresets.swift
//  AgenticHealthCoach
//

import Foundation

enum ScenarioPreset: String, CaseIterable, Identifiable {
    case s1PoorSleepBusyMorning
    case s2ProlongedInactivity
    case s3PreDeadlineStress
    case s4PostWorkoutRecovery
    case custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .s1PoorSleepBusyMorning: "S1 — Poor Sleep + Busy Morning"
        case .s2ProlongedInactivity:  "S2 — Prolonged Inactivity"
        case .s3PreDeadlineStress:    "S3 — Pre-Deadline Stress"
        case .s4PostWorkoutRecovery:  "S4 — Post-Workout Recovery"
        case .custom:                 "Custom"
        }
    }

    var defaultBlockTag: String {
        switch self {
        case .s1PoorSleepBusyMorning: "1"
        case .s2ProlongedInactivity:  "2"
        case .s3PreDeadlineStress:    "2"
        case .s4PostWorkoutRecovery:  "1"
        case .custom:                 ""
        }
    }

    var summary: String {
        switch self {
        case .s1PoorSleepBusyMorning:
            "Tue 8:30 AM. Slept 4h32m (bed 2:30 AM). Lecture 9 AM, tutoring 11 AM, quiz 1 PM."
        case .s2ProlongedInactivity:
            "Midterms week. Sitting in library for 4 hours. Free time ahead."
        case .s3PreDeadlineStress:
            "9 PM before a deadline. Elevated HR (92 bpm), low HRV (28 ms)."
        case .s4PostWorkoutRecovery:
            "Just finished a 45-min hard run. High exertion. No events for 90 min."
        case .custom:
            "Build a snapshot from scratch. Edits persist while this preset is selected."
        }
    }

    var isCustom: Bool { self == .custom }

    /// Returns a synthetic snapshot and the simulated "now" the prompt should use.
    /// Custom returns an empty snapshot at "now" — the caller is expected to ignore this and use stored draft state instead.
    func makeSnapshot() -> (snapshot: ContextSnapshot, now: Date) {
        switch self {
        case .custom:
            let now = Date()
            return (ContextSnapshot(timestamp: now), now)
        case .s1PoorSleepBusyMorning:
            let now = nextWeekday(.tuesday, hour: 8, minute: 30)
            let snap = ContextSnapshot(
                timestamp: now,
                stepsToday: 250,
                sleepHoursLastNight: 4.53,
                activeEnergyKcalToday: 30,
                latestHeartRateBPM: 72,
                latestHRVms: 45,
                workoutsLast7Days: 2,
                nextEventStart: now.addingTimeInterval(30 * 60),
                minutesUntilNextEvent: 30
            )
            return (snap, now)

        case .s2ProlongedInactivity:
            let now = nextWeekday(.wednesday, hour: 15, minute: 0)
            let snap = ContextSnapshot(
                timestamp: now,
                stepsToday: 600,
                sleepHoursLastNight: 7.2,
                activeEnergyKcalToday: 80,
                latestHeartRateBPM: 65,
                latestHRVms: 60,
                workoutsLast7Days: 1,
                nextEventStart: nil,
                minutesUntilNextEvent: nil
            )
            return (snap, now)

        case .s3PreDeadlineStress:
            let now = nextWeekday(.thursday, hour: 21, minute: 0)
            let snap = ContextSnapshot(
                timestamp: now,
                stepsToday: 4200,
                sleepHoursLastNight: 6.0,
                activeEnergyKcalToday: 220,
                latestHeartRateBPM: 92,
                latestHRVms: 28,
                workoutsLast7Days: 2,
                nextEventStart: nil,
                minutesUntilNextEvent: nil
            )
            return (snap, now)

        case .s4PostWorkoutRecovery:
            let now = nextWeekday(.saturday, hour: 10, minute: 30)
            let snap = ContextSnapshot(
                timestamp: now,
                stepsToday: 6800,
                sleepHoursLastNight: 7.5,
                activeEnergyKcalToday: 600,
                latestHeartRateBPM: 110,
                latestHRVms: 55,
                workoutsLast7Days: 4,
                nextEventStart: now.addingTimeInterval(90 * 60),
                minutesUntilNextEvent: 90
            )
            return (snap, now)
        }
    }

    private enum Weekday: Int { case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday }

    private func nextWeekday(_ weekday: Weekday, hour: Int, minute: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let now = Date()
        var components = cal.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        guard var candidate = cal.date(from: components) else { return now }
        while cal.component(.weekday, from: candidate) != weekday.rawValue || candidate < now {
            candidate = cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }
}
