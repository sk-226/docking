import SwiftUI

public struct ControlCenterView: View {
    @EnvironmentObject private var model: DockingAppModel

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: $model.controlCenterSelection) {
                Section("Dock") {
                    ForEach(ControlCenterSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Docking")
        } detail: {
            detail(for: model.controlCenterSelection)
        }
    }

    @ViewBuilder
    private func detail(for section: ControlCenterSection) -> some View {
        switch section {
        case .overview:
            ControlCenterOverview()
                .environmentObject(model)
        case .general:
            GeneralControlCenterSection()
        case .appearance:
            AppearanceControlCenterSection()
        case .apps:
            AppsControlCenterSection()
                .padding(24)
        case .widgets:
            WidgetsControlCenterSection()
        case .restore:
            DockRestoreView()
        }
    }
}

enum ControlCenterSection: String, CaseIterable, Identifiable {
    case overview
    case general
    case appearance
    case apps
    case widgets
    case restore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .general:
            return "General"
        case .appearance:
            return "Appearance"
        case .apps:
            return "Apps"
        case .widgets:
            return "Widgets"
        case .restore:
            return "Restore"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "dock.rectangle"
        case .general:
            return "gearshape"
        case .appearance:
            return "paintbrush"
        case .apps:
            return "app.badge"
        case .widgets:
            return "calendar.badge.clock"
        case .restore:
            return "arrow.counterclockwise"
        }
    }
}

private struct ControlCenterOverview: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Image(systemName: "dock.rectangle")
                        .font(.system(size: 34, weight: .semibold))
                    VStack(alignment: .leading) {
                        Text("Docking")
                            .font(.largeTitle.weight(.semibold))
                        Text("A native overlay dock with local calendar and weather widgets.")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Dock")
                        .font(.headline)
                    Text(overviewMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button {
                            model.showDock()
                        } label: {
                            Label("Show Dock", systemImage: "dock.rectangle")
                        }

                        Button {
                            model.hideDock()
                        } label: {
                            Label("Hide Dock", systemImage: "dock.rectangle")
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Configure")
                        .font(.headline)
                    Text("Use the sidebar for dock behavior, appearance, apps, widgets, and restore tools.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            // A short Overview can otherwise end up with an underspecified
            // detail-column layout inside NavigationSplitView after window
            // restoration. The explicit frame is not decorative; it tells
            // SwiftUI this page owns the available detail area even though it no
            // longer contains the wide diagnostic grid that used to force a
            // stable size.
            .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var overviewMessage: String {
        // Overview is the first page many users see, so it should not become a
        // diagnostic dashboard. Counts, display anchors, and other tuning state
        // stay in their dedicated sections where users are already making that
        // kind of decision. Here we only explain the immediate behavior that can
        // make Docking feel missing or present.
        switch model.settings.dockVisibility {
        case .autoHide:
            return "Docking is set to auto-hide. Move the pointer to the screen edge to reveal it, or use Show Dock now."
        case .alwaysVisible:
            return "Docking is set to stay visible. Use Hide Dock if you need it out of the way temporarily."
        }
    }
}
