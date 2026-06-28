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
            GeneralSettingsTab()
        case .appearance:
            AppearanceSettingsTab()
        case .apps:
            AppListSettingsSection()
                .padding(24)
        case .widgets:
            WidgetsSettingsTab()
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
        VStack(alignment: .leading, spacing: 20) {
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

            VStack(alignment: .leading, spacing: 14) {
                Text("Dock")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("Position")
                        Text(model.settings.dockPosition.label)
                    }
                    GridRow {
                        Text("Apps")
                        Text("\(model.dockItems.count)")
                    }
                    GridRow {
                        Text("Widgets")
                        Text("\(model.enabledWidgetCount) enabled")
                    }
                    GridRow {
                        Text("Dock visibility")
                        Picker("Dock visibility", selection: $model.settings.dockVisibility) {
                            ForEach(DockVisibilityMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    if model.settings.dockVisibility == .autoHide {
                        GridRow {
                            Text("Auto-hide delay")
                            Text(String(format: "%.1f sec", model.settings.autoHideDelay))
                        }
                    }
                }
                .foregroundStyle(.primary)

                Text("Actions")
                    .font(.headline)

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

            Spacer()
        }
        .padding(24)
    }
}
