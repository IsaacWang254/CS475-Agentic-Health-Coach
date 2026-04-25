//
//  EventKitManager.swift
//  AgenticHealthCoach
//

import Foundation
import EventKit

struct CalendarContext {
    var nextEventStart: Date?
    var minutesUntilNextEvent: Int?
    var isBusyNow: Bool
    var nextFreeWindow: DateInterval?
}

@Observable
final class EventKitManager {
    enum AuthorizationState {
        case notDetermined
        case requesting
        case authorized
        case denied
        case restricted
        case failed(Error)
    }

    static let shared = EventKitManager()

    let store = EKEventStore()
    private(set) var state: AuthorizationState = .notDetermined

    func requestAuthorization() async {
        state = .requesting
        do {
            let granted = try await store.requestFullAccessToEvents()
            state = granted ? .authorized : .denied
        } catch {
            state = .failed(error)
        }
    }

    func upcomingEvents(within hours: Double = 24) -> [EKEvent] {
        let now = Date()
        let end = now.addingTimeInterval(hours * 3600)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }

    func currentContext(freeWindowMinDuration: TimeInterval = 20 * 60) -> CalendarContext {
        let now = Date()
        let events = upcomingEvents(within: 24)

        let isBusyNow = events.contains { $0.startDate <= now && $0.endDate > now }
        let next = events.first { $0.startDate > now }
        let minutesUntil = next.map { Int($0.startDate.timeIntervalSince(now) / 60) }
        let free = nextFreeWindow(after: now, events: events, minDuration: freeWindowMinDuration)

        return CalendarContext(
            nextEventStart: next?.startDate,
            minutesUntilNextEvent: minutesUntil,
            isBusyNow: isBusyNow,
            nextFreeWindow: free
        )
    }

    private func nextFreeWindow(after start: Date, events: [EKEvent], minDuration: TimeInterval) -> DateInterval? {
        let horizon = start.addingTimeInterval(24 * 3600)
        var cursor = start
        for event in events where event.endDate > cursor {
            if event.startDate > cursor {
                let gap = event.startDate.timeIntervalSince(cursor)
                if gap >= minDuration {
                    return DateInterval(start: cursor, end: event.startDate)
                }
            }
            cursor = max(cursor, event.endDate)
            if cursor >= horizon { break }
        }
        if horizon.timeIntervalSince(cursor) >= minDuration {
            return DateInterval(start: cursor, end: horizon)
        }
        return nil
    }
}
