import SwiftUI

struct CalendarWidgetView: View {
    @EnvironmentObject private var model: DockingAppModel
    @ObservedObject var viewModel: CalendarWidgetViewModel

    var body: some View {
        let presentation = CalendarDockPresentation(
            event: viewModel.events.first,
            state: viewModel.state,
            showsLocation: model.settings.calendarShowsLocation
        )
        let preset = model.settings.calendarWidgetSizePreset

        DockWidgetShell(
            title: "Calendar",
            systemImage: presentation.symbolName,
            iconStyle: .calendar,
            iconScale: 1,
            width: model.settings.calendarWidgetWidth,
            height: model.settings.widgetTileHeight
        ) {
            model.toggleWidgetPanel(.calendar)
        } content: {
            if model.settings.dockPosition.isVertical {
                Text(presentation.compactPrimary)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            } else {
                CalendarDockContent(presentation: presentation, preset: preset)
            }
        }
        .background(WidgetFrameReporter(kind: .calendar))
        .accessibilityValue([presentation.primary, presentation.secondary, presentation.tertiary].compactMap { $0 }.joined(separator: ", "))
    }
}

private struct CalendarDockContent: View {
    let presentation: CalendarDockPresentation
    let preset: WidgetSizePreset

    var body: some View {
        switch preset {
        case .compact:
            compactContent
        case .standard:
            standardContent
        case .detailed:
            detailedContent
        }
    }

    private var compactContent: some View {
        Text(presentation.compactPrimary)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            DockWidgetLine(presentation.primary, font: .system(size: 11, weight: .semibold))
            DockWidgetLine(presentation.secondary, font: .system(size: 10), isSecondary: true)
        }
    }

    private var detailedContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(presentation.primary)
                    .font(.system(size: 10, weight: .medium))
                    .fixedSize()
                Text(presentation.detailLines.first ?? "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            DockWidgetLine(presentation.secondary, font: .system(size: 11, weight: .semibold))
        }
    }

}

struct CalendarDockPresentation {
    let compactPrimary: String
    let primary: String
    let secondary: String
    let detailLines: [String]
    let symbolName: String

    var tertiary: String? {
        detailLines.isEmpty ? nil : detailLines.joined(separator: " - ")
    }

    let event: CalendarEventSummary?

    init(
        event: CalendarEventSummary?,
        state: CalendarWidgetState,
        showsLocation: Bool,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) {
        self.event = event

        guard let event else {
            // Empty and permission states should not masquerade as schedule
            // data. Keeping them as short action/status labels makes the dock
            // glanceable and pushes explanatory copy into the panel/settings
            // where the user has enough room to act on it.
            switch state {
            case .permissionNotDetermined:
                compactPrimary = "Access"
                primary = "Access"
                secondary = "Calendar"
                detailLines = ["Permission", "Open widget"]
            case .permissionDenied:
                compactPrimary = "Off"
                primary = "Calendar"
                secondary = "Access off"
                detailLines = ["Permission", "System Settings"]
            case .permissionRestricted:
                compactPrimary = "Off"
                primary = "Calendar"
                secondary = "Restricted"
                detailLines = ["Permission", "Policy"]
            case .permissionWriteOnly:
                compactPrimary = "Off"
                primary = "Calendar"
                secondary = "Write-only"
                detailLines = ["Permission", "Full access"]
            case .loading:
                compactPrimary = "..."
                primary = "Loading"
                secondary = "Events"
                detailLines = ["Updating", "Calendar"]
            case .error:
                compactPrimary = "Error"
                primary = "Calendar"
                secondary = "Error"
                detailLines = ["Could not load", "Refresh"]
            default:
                compactPrimary = "Today"
                primary = "Today"
                secondary = "No events"
                detailLines = ["Free", "Calendar"]
            }
            symbolName = "calendar"
            return
        }

        let start = DockingFormatters.timeFormatter.string(from: event.startDate)
        let end = DockingFormatters.timeFormatter.string(from: event.endDate)
        let day = DockingFormatters.sectionTitle(for: event.startDate, calendar: calendar, now: now)
        let context = Self.contextLine(for: event, showsLocation: showsLocation)

        // Calendar is a scheduling widget, so time wins the first read. The
        // title is still the semantic content, but leading with the clock keeps
        // the compact/standard sizes useful even when the event title is long.
        compactPrimary = start
        primary = "\(start)-\(end)"
        secondary = event.title.nilIfBlank ?? "Untitled event"
        detailLines = [day.nilIfBlank, context].compactMap { $0 }
        symbolName = "calendar"
    }

    private static func contextLine(for event: CalendarEventSummary, showsLocation: Bool) -> String? {
        if showsLocation, let location = event.location?.nilIfBlank {
            return location
        }

        // Calendar name is the fallback because it is a routing cue, not
        // decorative metadata. We avoid showing both location and calendar in
        // the dock; the panel can afford that, but the dock should preserve one
        // short supporting line so the event title remains readable.
        return event.calendarName.nilIfBlank
    }
}
