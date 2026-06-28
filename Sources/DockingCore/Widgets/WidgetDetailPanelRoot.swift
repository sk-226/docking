import SwiftUI

struct WidgetDetailPanelRoot: View {
    @EnvironmentObject private var model: DockingAppModel
    let kind: DockWidgetKind

    var body: some View {
        Group {
            switch kind {
            case .calendar:
                CalendarDetailPanelView()
            case .weather:
                WeatherDetailPanelView()
            }
        }
        .preferredColorScheme(model.settings.theme.colorScheme)
        .tint(model.settings.accentColor)
    }
}

struct PermissionStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
