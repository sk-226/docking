import SwiftUI

struct DockItemView: View {
    @EnvironmentObject private var model: DockingAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: DockItem
    var isTransientRunningItem = false
    @State private var isHovering = false
    @State private var confirmsForceQuit = false

    private var isRunning: Bool {
        model.isRunning(item)
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
            if isRunning {
                Button("Show All Windows") {
                    model.showAllWindows(item)
                }
                Button("Hide") {
                    model.hideApplication(item)
                }
                Button("Quit") {
                    model.quit(item)
                }
                Button("Force Quit...", role: .destructive) {
                    confirmsForceQuit = true
                }
            }
            Button("Show in Finder") {
                model.showInFinder(item)
            }
            Divider()
            if isTransientRunningItem {
                Button("Keep in Docking") {
                    model.pinRunningItem(item)
                }
            } else {
                Button("Remove from Docking", role: .destructive) {
                    model.remove(item)
                }
            }
            Divider()
            Button("Open Control Center") {
                model.openControlCenterWindow()
            }
        }
        .confirmationDialog(
            "Force quit \(item.title)?",
            isPresented: $confirmsForceQuit,
            titleVisibility: .visible
        ) {
            Button("Force Quit", role: .destructive) {
                model.forceQuit(item)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This immediately terminates \(item.title). Unsaved changes in that app may be lost.")
        }
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens \(item.title)")
    }

    private var accessibilityValue: String {
        if isTransientRunningItem {
            return "Running, not kept in Docking"
        }
        return isRunning ? "Running" : "Not running"
    }
}
