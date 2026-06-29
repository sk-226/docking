import Foundation

enum DockingFormatters {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        // A 24-hour default matches the goal file and avoids ambiguous compact
        // panel rows. We still let DateFormatter localize digits and separators.
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        // Restore snapshots are operational checkpoints, so the user needs both
        // date and time to distinguish "before primary mode" from later manual
        // Dock edits. A localized template keeps the text compact without
        // assuming a US/Japanese ordering.
        formatter.setLocalizedDateFormatFromTemplate("MMM d HH:mm")
        return formatter
    }()

    static func durationString(from startDate: Date, to endDate: Date) -> String {
        let seconds = max(0, Int(endDate.timeIntervalSince(startDate)))
        let minutes = seconds / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        // We intentionally avoid DateComponentsFormatter here because its
        // localized abbreviated output varies enough to make the narrow dock
        // panel harder to scan and harder to test. This compact form keeps the
        // same shape across locales while still using plain, understandable text.
        if hours > 0 && remainingMinutes > 0 {
            return "\(hours) hr \(remainingMinutes) min"
        }
        if hours > 0 {
            return "\(hours) hr"
        }
        return "\(remainingMinutes) min"
    }

    static func sectionTitle(for date: Date, calendar: Calendar = .autoupdatingCurrent, now: Date = Date()) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }

        return shortDateFormatter.string(from: date)
    }

    static func temperature(_ value: Double, unit: TemperatureUnit) -> String {
        "\(Int(value.rounded()))°"
    }

    static func seconds(_ value: Double) -> String {
        let hundredths = Int((max(0, value) * 100).rounded())
        let seconds = Double(hundredths) / 100

        // Auto-hide delay is tuned in 0.05s increments. A fixed one-decimal
        // label would turn 0.05s into "0.1 sec", hiding the fast setting the
        // user deliberately chose; a fixed two-decimal label would make normal
        // values like 0.7s look noisy. This keeps the precision only where it
        // carries meaning.
        if hundredths.isMultiple(of: 100) {
            return String(format: "%.0f sec", seconds)
        }
        if hundredths.isMultiple(of: 10) {
            return String(format: "%.1f sec", seconds)
        }
        return String(format: "%.2f sec", seconds)
    }
}

enum CalendarGrouping {
    static func groupEvents(_ events: [CalendarEventSummary], calendar: Calendar = .autoupdatingCurrent) -> [(title: String, events: [CalendarEventSummary])] {
        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startDate)
        }

        return grouped
            .keys
            .sorted()
            .map { day in
                (
                    title: DockingFormatters.sectionTitle(for: day, calendar: calendar),
                    events: grouped[day, default: []].sorted { $0.startDate < $1.startDate }
                )
            }
    }
}

enum WeatherCodeMapping {
    static func label(for code: Int?) -> String {
        guard let code else { return "Weather" }

        // Open-Meteo follows WMO-style numeric conditions, while WeatherKit
        // already hands us provider-owned prose and symbols. These labels are
        // therefore only for the Open-Meteo fallback path. We keep code 3 as
        // "Cloudy" instead of the more literal "Overcast" because the dock
        // tile is a compact glance surface and "Cloudy" matches the broader
        // Apple-style condition vocabulary used elsewhere in this widget.
        switch code {
        case 0:
            return "Clear"
        case 1:
            return "Mostly Clear"
        case 2:
            return "Partly Cloudy"
        case 3:
            return "Cloudy"
        case 45, 48:
            return "Fog"
        case 51...67:
            return "Drizzle"
        case 71...77:
            return "Snow"
        case 80...82:
            return "Showers"
        case 95...99:
            return "Storm"
        default:
            return "Weather"
        }
    }

    static func symbolName(for code: Int?) -> String {
        guard let code else { return "cloud" }

        // Open-Meteo gives us WMO condition codes, not SF Symbols. Keep the
        // low-cloud-cover cases split instead of folding `1...3`: code 3 is
        // overcast, so `cloud.sun` would invent visible sun that the data
        // source did not report. Code 1 stays `sun.max` because making it
        // `cloud.sun` would collapse "mostly clear" into the same visual as
        // "partly cloudy"; if we later add Open-Meteo `is_day`, day/night
        // variants should be threaded through explicitly rather than guessed
        // from the weather code alone.
        switch code {
        case 0:
            return "sun.max"
        case 1:
            return "sun.max"
        case 2:
            return "cloud.sun"
        case 3:
            return "cloud"
        case 45, 48:
            return "cloud.fog"
        case 51...67, 80...82:
            return "cloud.rain"
        case 71...77:
            return "cloud.snow"
        case 95...99:
            return "cloud.bolt.rain"
        default:
            return "cloud"
        }
    }
}
