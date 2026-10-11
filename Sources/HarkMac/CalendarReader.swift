import EventKit
import Foundation
import HarkCore

/// The user's calendar, read-only, from the calendar store on this Mac. Hark asks for access only when a calendar
/// question is first asked, never writes, and keeps event titles on screen and out of every model.
@MainActor final class CalendarReader {
    struct Event: Sendable {
        let title: String
        let start: Date
        let end: Date
        let link: URL?
        let isAllDay: Bool
    }

    static let shared = CalendarReader()
    private let store = EKEventStore()

    enum Problem: LocalizedError {
        case denied
        var errorDescription: String? { "Allow Calendars for Hark in System Settings, Privacy & Security, Calendars." }
    }

    private func ensureAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            if !granted { throw Problem.denied }
        default: throw Problem.denied
        }
    }

    func events(from start: Date, to end: Date) async throws -> [Event] {
        try await ensureAccess()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }.map { event in
            Event(
                title: event.title ?? "Busy", start: event.startDate, end: event.endDate,
                link: CalendarCommand.firstLink(in: [event.url?.absoluteString, event.location, event.notes]),
                isAllDay: event.isAllDay)
        }
    }
}
