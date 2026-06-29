import EventKit
import Foundation

enum CalendarProviderError: LocalizedError {
    case notDetermined
    case denied
    case restricted
    case writeOnly

    var errorDescription: String? {
        switch self {
        case .notDetermined:
            return "Calendar permission has not been requested yet."
        case .denied:
            return "Calendar access is off. Enable it in System Settings to show events."
        case .restricted:
            return "Calendar access is restricted by system policy."
        case .writeOnly:
            return "Calendar access is write-only, so upcoming events cannot be displayed."
        }
    }
}

enum CalendarAuthorizationState: Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
    case writeOnly
}

protocol CalendarProviding: AnyObject {
    var changeNotificationName: Notification.Name { get }
    var changeNotificationObject: Any? { get }
    var authorizationState: CalendarAuthorizationState { get }
    func availableCalendars() async throws -> [CalendarSourceSummary]
    func upcomingEvents(lookaheadDays: Int, maxEvents: Int, selectedCalendarIDs: [String]) async throws -> [CalendarEventSummary]
}

final class EventKitCalendarProvider: CalendarProviding {
    private let store = EKEventStore()

    var changeNotificationName: Notification.Name {
        .EKEventStoreChanged
    }

    var changeNotificationObject: Any? {
        store
    }

    var authorizationState: CalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .authorized, .fullAccess:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .writeOnly:
            return .writeOnly
        @unknown default:
            return .denied
        }
    }

    func availableCalendars() async throws -> [CalendarSourceSummary] {
        try await ensureAccess()

        return store.calendars(for: .event)
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map { calendar in
                CalendarSourceSummary(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    colorHex: calendar.cgColor.flatMap(Self.hexString)
                )
            }
    }

    func upcomingEvents(lookaheadDays: Int, maxEvents: Int, selectedCalendarIDs: [String]) async throws -> [CalendarEventSummary] {
        try await ensureAccess()

        let now = Date()
        let end = Calendar.autoupdatingCurrent.date(byAdding: .day, value: max(1, lookaheadDays), to: now) ?? now
        let calendars = calendarsMatching(selectedCalendarIDs)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)

        // EventKit's query is synchronous. We keep the requested date window
        // short and bounded by settings, then sort/trim before returning so the
        // UI never has to hold an unbounded event list.
        return store.events(matching: predicate)
            .filter { !$0.isDetached && !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(max(1, maxEvents))
            .map { event in
                CalendarEventSummary(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled Event",
                    calendarName: event.calendar?.title ?? "Calendar",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    location: event.location
                )
            }
    }

    private func calendarsMatching(_ selectedCalendarIDs: [String]) -> [EKCalendar]? {
        let selected = Set(selectedCalendarIDs)
        guard !selected.isEmpty else {
            return nil
        }

        let matched = store.calendars(for: .event)
            .filter { selected.contains($0.calendarIdentifier) }

        // If stored IDs no longer exist, treat it as "all calendars" rather than
        // showing an empty widget forever. Calendar identifiers can change when
        // accounts are removed/re-added, so stale settings should degrade gently.
        return matched.isEmpty ? nil : matched
    }

    private static func hexString(for color: CGColor) -> String? {
        guard let components = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB) ?? color.colorSpace ?? CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else {
            return nil
        }

        let red = Int((components[0] * 255).rounded())
        let green = Int((components[1] * 255).rounded())
        let blue = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func ensureAccess() async throws {
        switch authorizationState {
        case .notDetermined:
            let granted = try await requestAccess()
            guard granted else {
                throw CalendarProviderError.denied
            }
        case .granted:
            return
        case .denied:
            throw CalendarProviderError.denied
        case .restricted:
            throw CalendarProviderError.restricted
        case .writeOnly:
            throw CalendarProviderError.writeOnly
        @unknown default:
            throw CalendarProviderError.denied
        }
    }

    private func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
