import SwiftUI

struct CalendarDetailPanelView: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Calendar")
                        .font(.title2.weight(.semibold))
                    Text(model.calendarViewModel.nextEventLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.calendarViewModel.refresh(settings: model.settings, reason: "manual") }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .dockTooltip("Refresh calendar")
                .accessibilityLabel("Refresh calendar")
                .accessibilityHint("Reloads upcoming events")
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dockingSurface(settings: model.settings, cornerRadius: 18)
        .task {
            await model.calendarViewModel.refreshIfNeeded(settings: model.settings)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.calendarViewModel.state {
        case .idle, .loading:
            if model.calendarViewModel.events.isEmpty {
                ProgressView("Loading events...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                calendarEventsList
            }
        case .permissionNotDetermined:
            PermissionStateView(
                systemImage: "calendar.badge.exclamationmark",
                title: "Calendar access is needed",
                message: "Use refresh or reopen this widget to grant access. Docking reads upcoming events locally through EventKit."
            )
        case .permissionDenied:
            PermissionStateView(
                systemImage: "lock.slash",
                title: "Calendar access is off",
                message: "Enable Calendar access in System Settings to show events."
            )
        case .permissionRestricted:
            PermissionStateView(
                systemImage: "lock.trianglebadge.exclamationmark",
                title: "Calendar access is restricted",
                message: "macOS policy is preventing readable Calendar access. Check Screen Time, device management, or Calendar privacy settings."
            )
        case .permissionWriteOnly:
            PermissionStateView(
                systemImage: "calendar.badge.exclamationmark",
                title: "Calendar access is write-only",
                message: "Docking needs full Calendar access to read upcoming events. Enable full access in System Settings."
            )
        case .empty:
            PermissionStateView(
                systemImage: "calendar",
                title: "No upcoming events",
                message: "No events were found in the configured lookahead window."
            )
        case .loaded:
            calendarEventsList
        case .error(let message):
            PermissionStateView(
                systemImage: "exclamationmark.triangle",
                title: "Calendar could not load",
                message: message
            )
        }
    }

    private var calendarEventsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.calendarViewModel.state == .loading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Updating events...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let nextEvent = CalendarDetailPanelPresentation.summaryEvent(from: model.calendarViewModel.events) {
                    CalendarNextEventSummary(event: nextEvent, showLocation: model.settings.calendarShowsLocation)
                }

                ForEach(
                    Array(CalendarDetailPanelPresentation.groupedEventsAfterSummary(model.calendarViewModel.events).enumerated()),
                    id: \.offset
                ) { _, group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Rectangle()
                                .fill(.secondary.opacity(0.18))
                                .frame(height: 1)
                        }

                        ForEach(group.events) { event in
                            CalendarEventRow(event: event, showLocation: model.settings.calendarShowsLocation)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum CalendarDetailPanelPresentation {
    static func summaryEvent(from events: [CalendarEventSummary]) -> CalendarEventSummary? {
        sortedEvents(events).first
    }

    static func groupedEventsAfterSummary(
        _ events: [CalendarEventSummary],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [(title: String, events: [CalendarEventSummary])] {
        let remainingEvents = Array(sortedEvents(events).dropFirst())
        return CalendarGrouping.groupEvents(remainingEvents, calendar: calendar)
    }

    private static func sortedEvents(_ events: [CalendarEventSummary]) -> [CalendarEventSummary] {
        // EventKit already returns upcoming events sorted, but this detail panel
        // also renders cached/test/provider-fallback data. Keeping the ordering
        // rule at the presentation boundary prevents a subtle UI regression
        // where "Next" could point at one event while the grouped schedule puts
        // an earlier event below it. We sort the tiny bounded event list here
        // instead of adding state to the ViewModel because this is view
        // presentation policy, not a data-fetching concern.
        events.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            if lhs.endDate != rhs.endDate {
                return lhs.endDate < rhs.endDate
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

private struct CalendarNextEventSummary: View {
    let event: CalendarEventSummary
    let showLocation: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 3, height: 58)

            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 1) {
                    Text(DockingFormatters.timeFormatter.string(from: event.startDate))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(DockingFormatters.durationString(from: event.startDate, to: event.endDate))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Next")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(event.title.nilIfBlank ?? "Untitled event")
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // The top item deserves more visual weight than the remaining schedule,
        // but it should still belong to the same glass panel. We use a flat
        // band and accent rail instead of a nested rounded card: the panel is
        // already a framed surface, and another card would make a compact
        // schedule popover feel heavier without adding information.
        .padding(.horizontal, 2)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.035))
    }

    private var metadataText: String {
        var pieces = [
            "Until \(DockingFormatters.timeFormatter.string(from: event.endDate))",
            event.calendarName
        ].compactMap { $0.nilIfBlank }

        if showLocation, let location = event.location?.nilIfBlank {
            pieces.append(location)
        }

        return pieces.joined(separator: " · ")
    }
}

private struct CalendarEventRow: View {
    let event: CalendarEventSummary
    let showLocation: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(DockingFormatters.timeFormatter.string(from: event.startDate))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(DockingFormatters.durationString(from: event.startDate, to: event.endDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 58, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 3, height: 34)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The row intentionally avoids a card background. A schedule panel is
        // scanned repeatedly, and carding every event made the small popover
        // feel heavier than macOS Calendar's list surfaces. The thin accent
        // rail supplies grouping without adding another rounded rectangle.
        .padding(.vertical, 3)
    }

    private var metadataText: String {
        var pieces = [
            "Until \(DockingFormatters.timeFormatter.string(from: event.endDate))",
            event.calendarName
        ].compactMap { $0.nilIfBlank }

        if showLocation, let location = event.location?.nilIfBlank {
            pieces.append(location)
        }

        return pieces.joined(separator: " · ")
    }
}
