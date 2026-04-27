//
//  WatchPayload.swift
//  AgenticHealthCoach
//

import Foundation

struct WatchPayload: Codable, Equatable {
    var recommendationID: String
    var goalDisplayName: String
    var message: String
    var explanation: String
    var timestamp: Date
    var stepsToday: Int?
    var sleepHoursLastNight: Double?
    var minutesUntilNextEvent: Int?

    static let userInfoKey = "watchPayload"
}
