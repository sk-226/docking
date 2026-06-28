import SwiftUI

struct CalendarWidgetView: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        DockWidgetShell(
            title: "Calendar",
            systemImage: "calendar",
            width: model.settings.calendarWidgetWidth,
            height: model.settings.widgetTileHeight
        ) {
            model.toggleWidgetPanel(.calendar)
        } content: {
            if model.settings.calendarWidgetSizePreset == .detailed {
                CalendarDetailedDockContent(
                    event: model.calendarViewModel.events.first,
                    state: model.calendarViewModel.state,
                    showsLocation: model.settings.calendarShowsLocation
                )
            } else {
                let compact = model.calendarViewModel.compactText
                DockWidgetLine(compact.primary, font: .system(size: 13, weight: .semibold, design: .rounded))
                DockWidgetLine(compact.secondary, font: .caption2, isSecondary: true)
            }
        }
        .background(WidgetFrameReporter(kind: .calendar))
    }
}

private struct CalendarDetailedDockContent: View {
    let event: CalendarEventSummary?
    let state: CalendarWidgetState
    let showsLocation: Bool

    var body: some View {
        let content = detailedText

        VStack(spacing: 1) {
            DockWidgetLine(content.primary, font: .caption.weight(.semibold))
            DockWidgetLine(content.secondary, font: .caption2, isSecondary: true)
            if let tertiary = content.tertiary {
                DockWidgetLine(tertiary, font: .system(size: 9), isSecondary: true)
            }
        }
    }

    private var detailedText: (primary: String, secondary: String, tertiary: String?) {
        guard let event else {
            switch state {
            case .permissionNotDetermined:
                return ("Access", "Calendar", "Needed")
            case .permissionDenied:
                return ("Calendar", "Access off", nil)
            case .loading:
                return ("Loading", "Events", nil)
            default:
                return ("Today", "No events", nil)
            }
        }

        let time = "\(DockingFormatters.timeFormatter.string(from: event.startDate))-\(DockingFormatters.timeFormatter.string(from: event.endDate))"
        let tertiary = showsLocation
            ? event.location?.nilIfBlank ?? event.calendarName
            : event.calendarName
        // The detailed dock tile earns its extra size by adding schedule
        // context, not by scaling the same two labels. Location is preferred
        // when the user opted into it; calendar name is the fallback because it
        // is still useful routing information and does not require extra data.
        return (time, event.title, tertiary)
    }
}
