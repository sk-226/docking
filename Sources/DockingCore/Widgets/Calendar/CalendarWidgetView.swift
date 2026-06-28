import SwiftUI

struct CalendarWidgetView: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        DockWidgetShell(title: "Calendar", systemImage: "calendar") {
            model.toggleWidgetPanel(.calendar)
        } content: {
            let compact = model.calendarViewModel.compactText
            Text(compact.primary)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
        .background(WidgetFrameReporter(kind: .calendar))
    }
}
