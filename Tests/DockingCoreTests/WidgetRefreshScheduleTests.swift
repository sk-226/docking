import Foundation
import XCTest
@testable import DockingCore

final class WidgetRefreshScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, in calendar: Calendar? = nil) -> Date {
        (calendar ?? self.calendar).date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func event(_ id: String, start: Date, end: Date) -> CalendarEventSummary {
        CalendarEventSummary(id: id, title: id, calendarName: "Work", startDate: start, endDate: end, location: nil)
    }

    private func nextCalendar(_ events: [CalendarEventSummary], now: Date) -> Date {
        WidgetRefreshSchedule.nextCalendarRefresh(events: events, now: now, calendar: calendar)
    }

    func testNoEventsWaitsForNextMidnight() {
        XCTAssertEqual(nextCalendar([], now: date(23, 15)), date(24, 0))
    }

    func testInProgressEventRefreshesAtItsEnd() {
        let meeting = event("meeting", start: date(23, 15), end: date(23, 16))
        XCTAssertEqual(nextCalendar([meeting], now: date(23, 15, 30)), date(23, 16))
    }

    func testEventEndingAfterMidnightStillRefreshesAtMidnight() {
        let lateShow = event("late", start: date(23, 22), end: date(24, 1))
        XCTAssertEqual(nextCalendar([lateShow], now: date(23, 22, 30)), date(24, 0))
    }

    func testEndedEventsAreIgnored() {
        let ended = event("ended", start: date(23, 9), end: date(23, 10))
        XCTAssertEqual(nextCalendar([ended], now: date(23, 15)), date(24, 0))
    }

    func testEarliestEndWinsOverFirstListedEvent() {
        let allDay = event("all-day", start: date(23, 0), end: date(24, 0))
        let standup = event("standup", start: date(23, 10), end: date(23, 10, 15))
        XCTAssertEqual(nextCalendar([allDay, standup], now: date(23, 9)), date(23, 10, 15))
    }

    func testMidnightFollowsTheCalendarTimeZone() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = date(23, 15)

        XCTAssertEqual(WidgetRefreshSchedule.nextCalendarRefresh(events: [], now: now, calendar: calendar), date(24, 0))
        XCTAssertEqual(
            WidgetRefreshSchedule.nextCalendarRefresh(events: [], now: now, calendar: losAngeles),
            date(23, 0, in: losAngeles)
        )
    }

    func testWeatherRefreshesOneIntervalAfterFetch() {
        let fetchedAt = date(23, 12)
        XCTAssertEqual(
            WidgetRefreshSchedule.nextWeatherRefresh(fetchedAt: fetchedAt, intervalMinutes: 30, now: date(23, 12, 5)),
            date(23, 12, 30)
        )
    }

    func testWeatherIntervalHasFifteenMinuteFloor() {
        let fetchedAt = date(23, 12)
        XCTAssertEqual(
            WidgetRefreshSchedule.nextWeatherRefresh(fetchedAt: fetchedAt, intervalMinutes: 5, now: fetchedAt),
            date(23, 12, 15)
        )
    }

    func testExpiredWeatherWaitsAFullIntervalBeforeRetrying() {
        XCTAssertEqual(
            WidgetRefreshSchedule.nextWeatherRefresh(fetchedAt: date(23, 9), intervalMinutes: 30, now: date(23, 12)),
            date(23, 12, 30)
        )
    }

    func testMissingWeatherWaitsAFullIntervalBeforeRetrying() {
        XCTAssertEqual(
            WidgetRefreshSchedule.nextWeatherRefresh(fetchedAt: nil, intervalMinutes: 60, now: date(23, 12)),
            date(23, 13)
        )
    }
}
