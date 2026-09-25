import Foundation

typealias WidgetRefreshSleep = (Date) async throws -> Void

enum WidgetRefreshSchedule {
    static func nextCalendarRefresh(events: [CalendarEventSummary], now: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86_400)
        // Events arrive sorted by start date, so the first event can be a long
        // or all-day item while a later, shorter one ends sooner. The detail
        // panel lists every event, so the earliest end among them is the next
        // moment the displayed data goes stale.
        guard let nextEnd = events.lazy.map(\.endDate).filter({ $0 > now }).min() else {
            return nextDay
        }
        return min(nextEnd, nextDay)
    }

    static func nextWeatherRefresh(fetchedAt: Date?, intervalMinutes: Int, now: Date) -> Date {
        let interval = Double(max(15, intervalMinutes)) * 60
        if let fetchedAt {
            let due = fetchedAt.addingTimeInterval(interval)
            if due > now {
                return due
            }
        }
        // A missing or already-expired snapshot means the last attempt did not
        // produce fresh data. Waiting a full interval keeps a failing provider
        // from being retried in a tight loop.
        return now.addingTimeInterval(interval)
    }

    static func sleep(until date: Date) async throws {
        // The continuous clock keeps counting through system sleep, so a
        // deadline that passed while the Mac slept fires right after wake.
        // Wall-clock jumps are handled by re-arming on NSSystemClockDidChange.
        try await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)), clock: .continuous)
    }
}
