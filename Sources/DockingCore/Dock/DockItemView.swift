import SwiftUI

struct DockItemView: View {
    @EnvironmentObject private var model: DockingAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: DockItem
    @State private var isHovering = false

    private var isRunning: Bool {
        guard let bundleIdentifier = item.bundleIdentifier else {
            return false
        }
        return model.runningBundleIDs.contains(bundleIdentifier)
    }

    private var isActive: Bool {
        item.bundleIdentifier == model.activeBundleID
    }

    var body: some View {
        let isVertical = model.settings.dockPosition.isVertical

        Button {
            model.launch(item)
        } label: {
            VStack(spacing: 4) {
                Image(nsImage: model.icon(for: item))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: model.settings.iconSize, height: model.settings.iconSize)
                    .scaleEffect(isHovering && !reduceMotion ? 1.08 : 1.0)

                Circle()
                    .fill(isActive ? model.settings.accentColor : (isRunning ? Color.primary.opacity(0.8) : Color.clear))
                    .frame(width: 5, height: 5)
            }
            .frame(
                width: isVertical ? model.settings.dockSize - 8 : model.settings.iconSize + 4,
                height: isVertical ? model.settings.iconSize + 10 : model.settings.dockSize - 8
            )
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .dockTooltip(item.title)
        .contextMenu {
            Button("Open") {
                model.launch(item)
            }
            Button("Show in Finder") {
                model.showInFinder(item)
            }
            Divider()
            Button("Remove from Docking", role: .destructive) {
                model.remove(item)
            }
            Divider()
            Button("Settings") {
                model.openSettingsWindow()
            }
        }
        .accessibilityLabel(item.title)
        .accessibilityValue(isRunning ? "Running" : "Not running")
        .accessibilityHint("Opens \(item.title)")
    }
}
