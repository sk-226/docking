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
    case general
    case appearance
    case apps
    case widgets
    case restore

    var id: String { rawValue }

    var title: String {
        switch self {
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
