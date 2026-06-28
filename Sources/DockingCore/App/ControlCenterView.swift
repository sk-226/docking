import SwiftUI

public struct ControlCenterView: View {
    @EnvironmentObject private var model: DockingAppModel
    @State private var selection: ControlCenterSection? = .overview

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
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
            detail(for: selection ?? .overview)
        }
    }

    @ViewBuilder
    private func detail(for section: ControlCenterSection) -> some View {
        switch section {
        case .overview:
            ControlCenterOverview()
                .environmentObject(model)
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

private enum ControlCenterSection: String, CaseIterable, Identifiable {
    case overview
    case apps
    case widgets
    case restore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
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

            Form {
                Section("Dock") {
                    LabeledContent("Position", value: model.settings.dockPosition.label)
                    LabeledContent("Apps", value: "\(model.dockItems.count)")
                    LabeledContent("Widgets", value: "\(model.enabledWidgetCount) enabled")
                    Picker("Dock visibility", selection: $model.settings.dockVisibility) {
                        ForEach(DockVisibilityMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if model.settings.dockVisibility == .autoHide {
                        LabeledContent("Auto-hide delay", value: String(format: "%.1f sec", model.settings.autoHideDelay))
                    }
                }

                Section("Actions") {
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

                        Button {
                            model.openSettingsWindow()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(24)
    }
}
