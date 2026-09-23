import AppKit
import SwiftUI

struct DockItemView: View {
    @EnvironmentObject private var model: DockingAppModel
    let item: DockItem
    let iconSize: Double
    var isTransientRunningItem = false
    var launchProgress = 0.0
    @State private var confirmsForceQuit = false

    private var isRunning: Bool {
        model.isRunning(item)
    }

    private var isTerminationPending: Bool {
        model.isTerminationPending(item)
    }

    var body: some View {
        let isVertical = model.settings.dockPosition.isVertical

        Button {
            model.performPrimaryClick(item, modifiers: NSEvent.modifierFlags)
        } label: {
            Color.clear
                .frame(width: isVertical ? iconSize + DockLayout.indicatorSpace : iconSize,
                       height: isVertical ? iconSize : iconSize + DockLayout.indicatorSpace)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dockTooltip(item.title)
        .overlay {
            DockItemInteraction(item: item, model: model, isTransient: isTransientRunningItem,
                                iconSize: iconSize, launchProgress: launchProgress) {
                confirmsForceQuit = true
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
        .accessibilityHint(item.isFolder ? "Opens the \(item.title) stack" : "Opens \(item.title)")
    }

    private var accessibilityValue: String {
        if !item.isApplication {
            return item.kind.label
        }
        if isTerminationPending {
            return "Quit requested"
        }
        if isTransientRunningItem {
            return "Running, not kept in Docking"
        }
        return isRunning ? "Running" : "Not running"
    }

}

enum DockTerminationMenuPolicy {
    static func title(optionKeyIsPressed: Bool) -> String {
        optionKeyIsPressed ? "Force Quit..." : "Quit"
    }
}

enum DockContextMenuPolicy {
    static let menuTitle = "DockingItemContextMenu"
    static let includesAppProvidedDockMenuItems = false

    static func isDockItemContextMenu(_ menu: NSMenu) -> Bool {
        menu.title == menuTitle
    }
}
