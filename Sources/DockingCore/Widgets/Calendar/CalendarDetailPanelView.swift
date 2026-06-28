import SwiftUI

struct CalendarDetailPanelView: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Upcoming")
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

                ForEach(Array(CalendarGrouping.groupEvents(model.calendarViewModel.events).enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.headline)
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

private struct CalendarEventRow: View {
    let event: CalendarEventSummary
    let showLocation: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.calendarName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(event.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text("\(DockingFormatters.timeFormatter.string(from: event.startDate))-\(DockingFormatters.timeFormatter.string(from: event.endDate)) · \(DockingFormatters.durationString(from: event.startDate, to: event.endDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showLocation, let location = event.location?.nilIfBlank {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
