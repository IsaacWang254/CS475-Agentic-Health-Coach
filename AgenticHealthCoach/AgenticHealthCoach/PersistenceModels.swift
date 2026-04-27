//
//  PersistenceModels.swift
//  AgenticHealthCoach
//

import Foundation
import SwiftData

enum HealthGoal: String, Codable, CaseIterable, Identifiable {
    case sleep, activity, stress, workoutConsistency
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sleep: "Sleep"
        case .activity: "Activity"
        case .stress: "Stress Management"
        case .workoutConsistency: "Workout Consistency"
        }
    }
}

enum AgentTone: String, Codable, CaseIterable, Identifiable {
    case empathetic, direct, analytical
    var id: String { rawValue }
}

@Model
final class UserPreferences {
    var goals: [HealthGoal]
    var personalGoals: String
    var tone: AgentTone
    var minHoursBetweenNudges: Int
    var quietHoursStart: Int
    var quietHoursEnd: Int
    var hasCompletedOnboarding: Bool

    init(
        goals: [HealthGoal] = [.sleep, .activity],
        personalGoals: String = "",
        tone: AgentTone = .empathetic,
        minHoursBetweenNudges: Int = 3,
        quietHoursStart: Int = 22,
        quietHoursEnd: Int = 7,
        hasCompletedOnboarding: Bool = false
    ) {
        self.goals = goals
        self.personalGoals = personalGoals
        self.tone = tone
        self.minHoursBetweenNudges = minHoursBetweenNudges
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

@Model
final class ContextSnapshot {
    var timestamp: Date
    var stepsToday: Int?
    var sleepHoursLastNight: Double?
    var activeEnergyKcalToday: Double?
    var latestHeartRateBPM: Double?
    var latestHRVms: Double?
    var workoutsLast7Days: Int
    var nextEventStart: Date?
    var minutesUntilNextEvent: Int?

    init(
        timestamp: Date = .now,
        stepsToday: Int? = nil,
        sleepHoursLastNight: Double? = nil,
        activeEnergyKcalToday: Double? = nil,
        latestHeartRateBPM: Double? = nil,
        latestHRVms: Double? = nil,
        workoutsLast7Days: Int = 0,
        nextEventStart: Date? = nil,
        minutesUntilNextEvent: Int? = nil
    ) {
        self.timestamp = timestamp
        self.stepsToday = stepsToday
        self.sleepHoursLastNight = sleepHoursLastNight
        self.activeEnergyKcalToday = activeEnergyKcalToday
        self.latestHeartRateBPM = latestHeartRateBPM
        self.latestHRVms = latestHRVms
        self.workoutsLast7Days = workoutsLast7Days
        self.nextEventStart = nextEventStart
        self.minutesUntilNextEvent = minutesUntilNextEvent
    }
}

@Model
final class Recommendation {
    var timestamp: Date
    var goal: HealthGoal
    var message: String
    var explanation: String
    var dismissed: Bool
    var actedOn: Bool

    init(
        timestamp: Date = .now,
        goal: HealthGoal,
        message: String,
        explanation: String,
        dismissed: Bool = false,
        actedOn: Bool = false
    ) {
        self.timestamp = timestamp
        self.goal = goal
        self.message = message
        self.explanation = explanation
        self.dismissed = dismissed
        self.actedOn = actedOn
    }
}
