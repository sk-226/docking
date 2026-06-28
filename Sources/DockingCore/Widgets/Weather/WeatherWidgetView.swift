import SwiftUI

struct WeatherWidgetView: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        DockWidgetShell(title: "Weather", systemImage: compact.symbol) {
            model.toggleWidgetPanel(.weather)
        } content: {
            Text(compact.primary)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .truncationMode(.tail)
            Text(compact.secondary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .truncationMode(.tail)
        }
        .background(WidgetFrameReporter(kind: .weather))
    }

    private var compact: (primary: String, secondary: String, symbol: String) {
        model.weatherViewModel.compactText
    }
}
