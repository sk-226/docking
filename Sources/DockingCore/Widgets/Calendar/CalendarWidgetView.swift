import SwiftUI

struct CalendarWidgetView: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        let presentation = CalendarDockPresentation(
            event: model.calendarViewModel.events.first,
            state: model.calendarViewModel.state,
            showsLocation: model.settings.calendarShowsLocation
        )
        let preset = model.settings.calendarWidgetSizePreset

        DockWidgetShell(
            title: "Calendar",
            systemImage: presentation.symbolName,
            iconStyle: .calendar,
            iconScale: preset == .detailed ? 1.25 : 1,
            width: model.settings.calendarWidgetWidth,
            height: model.settings.widgetTileHeight
        ) {
            model.toggleWidgetPanel(.calendar)
        } content: {
            CalendarDockContent(presentation: presentation, preset: preset)
        }
        .background(WidgetFrameReporter(kind: .calendar))
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
        VStack(spacing: 0) {
            DockWidgetLine(
                presentation.compactPrimary,
                font: .system(size: 13, weight: .semibold, design: .rounded)
            )
            DockWidgetLine(
                presentation.secondary,
                font: .system(size: 9, weight: .medium),
                isSecondary: true
            )
        }
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            DockWidgetLine(
                presentation.primary,
                font: .system(size: 12, weight: .semibold, design: .rounded)
            )
            DockWidgetLine(
                presentation.secondary,
                font: .system(size: 10, weight: .medium),
                isSecondary: true
            )
        }
    }

    private var detailedContent: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                DockWidgetLine(
                    presentation.primary,
                    font: .system(size: 12, weight: .semibold, design: .rounded)
                )
                DockWidgetLine(
                    presentation.detailLines.first ?? presentation.secondary,
                    font: .system(size: 9, weight: .medium),
                    isSecondary: true
                )
            }
            .frame(width: 66, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                DockWidgetLine(
                    presentation.secondary,
                    font: .system(size: 11, weight: .semibold)
                )
                if let tertiary = presentation.detailLines.dropFirst().first {
                    DockWidgetLine(
                        tertiary,
                        font: .system(size: 9, weight: .medium),
                        isSecondary: true
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
