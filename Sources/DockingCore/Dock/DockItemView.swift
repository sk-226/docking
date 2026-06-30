import AppKit
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
        model.isActive(item)
    }

    private var isTerminationPending: Bool {
        model.isTerminationPending(item)
    }

    var body: some View {
        let isVertical = model.settings.dockPosition.isVertical
        let hoverScale: CGFloat = isHovering && !reduceMotion ? 1.08 : 1.0

        Button {
            if NSEvent.modifierFlags.contains(.command) {
                // Match the long-standing Dock shortcut: Command-click asks
                // Finder to reveal the backing app bundle or folder instead of
                // launching the app or opening the stack. This intentionally
                // lives in the primary click path, not only the context menu,
                // because the shortcut is muscle memory for macOS Dock users.
                model.showInFinder(item)
            } else if item.isFolder {
                model.toggleFolderStack(item)
            } else {
                model.launch(item)
            }
        } label: {
            VStack(spacing: 4) {
                Image(nsImage: model.icon(for: item))
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: model.settings.iconSize, height: model.settings.iconSize)
                    .scaleEffect(hoverScale)

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
            .background(DockItemFrameReporter(itemID: item.id))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .dockTooltip(item.title)
        .contextMenu {
            contextMenuContent
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
        if item.isFolder {
            return "Folder"
        }
        if isTransientRunningItem {
            return "Running, not kept in Docking"
        }
        if isTerminationPending {
            return "Quit requested"
        }
        return isRunning ? "Running" : "Not running"
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if item.isFolder {
            folderContextMenu
        } else {
            applicationContextMenu
        }
    }

    @ViewBuilder
    private var applicationContextMenu: some View {
        // The system Dock menu is not a pure operating-system template. Apps
        // can prepend their own entries through AppKit's dock-menu hooks, which
        // is why Notion Calendar can expose a stronger "Quit Completely" style
        // command while many ordinary apps cannot. Docking intentionally does
        // not try to copy those app-provided entries: there is no public,
        // cross-process API for asking another app for its Dock menu or for
        // invoking one of those commands with the target app's own semantics.
        // Mirroring only the generic actions below keeps the menu honest about
        // what Docking can implement itself, and avoids turning normal Quit
        // into an app-specific resident-process teardown command.
        Button("Open") {
            model.launch(item)
        }
        .disabled(isTerminationPending)
        if isTerminationPending {
            // A pending Quit is deliberately not treated as "not running yet".
            // Showing a disabled status row keeps the menu honest while
            // preventing the tempting Open action from becoming an accidental
            // relaunch during an app's asynchronous shutdown.
            Button("Quitting...") {}
                .disabled(true)
        } else if isRunning {
            Button("Show All Windows") {
                model.showAllWindows(item)
            }
            Button("Hide") {
                model.hideApplication(item)
            }
            Button(terminationMenuTitle, role: usesForceQuitMenuItem ? .destructive : nil) {
                if usesForceQuitMenuItem {
                    confirmsForceQuit = true
                } else {
                    model.quit(item)
                }
            }
        }
        sharedOptionsMenu
        dockingMenu
    }

    @ViewBuilder
    private var folderContextMenu: some View {
        Button("Open") {
            model.launch(item)
        }
        Menu("Sort By") {
            ForEach(DockFolderSortMode.allCases) { mode in
                Button {
                    model.updateFolderSortMode(mode, for: item)
                } label: {
                    checkmarkedLabel(mode.label, isSelected: item.folderSortMode == mode)
                }
            }
        }
        Menu("Display as") {
            ForEach(DockFolderDisplayMode.allCases) { mode in
                Button {
                    model.updateFolderDisplayMode(mode, for: item)
                } label: {
                    checkmarkedLabel(mode.label, isSelected: item.folderDisplayMode == mode)
                }
            }
        }
        Menu("View content as") {
            ForEach(DockFolderViewMode.allCases) { mode in
                Button {
                    model.updateFolderViewMode(mode, for: item)
                } label: {
                    checkmarkedLabel(mode.label, isSelected: item.folderViewMode == mode)
                }
            }
        }
        sharedOptionsMenu
        dockingMenu
    }

    @ViewBuilder
    private var sharedOptionsMenu: some View {
        Divider()
        Menu("Options") {
            if isTransientRunningItem {
                Button("Keep in Docking") {
                    model.pinRunningItem(item)
                }
            } else {
                Button("Remove from Docking") {
                    model.remove(item)
                }
            }
            Button("Show in Finder") {
                model.showInFinder(item)
            }
        }
    }

    @ViewBuilder
    private var dockingMenu: some View {
        Divider()
        Menu("Docking") {
            // Keep Docking-specific actions out of the standard Dock action
            // stack. Users should be able to scan Open/Show/Hide/Quit and
            // folder stack options as Dock-like controls first, then find
            // Docking configuration without mistaking it for an Apple Dock
            // command.
            Button("Open Control Center") {
                model.openControlCenterWindow()
            }
        }
    }

    @ViewBuilder
    private func checkmarkedLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var usesForceQuitMenuItem: Bool {
        // The macOS Dock does not show Quit and Force Quit as parallel ordinary
        // choices. In the common public interaction, Option changes Quit into
        // Force Quit. SwiftUI's contextMenu does not provide Dock-private live
        // menu validation, so we sample the modifier state while constructing
        // the menu and keep the normal menu aligned with the standard Dock
        // shape: exactly one termination command is visible.
        NSEvent.modifierFlags.contains(.option)
    }

    private var terminationMenuTitle: String {
        DockTerminationMenuPolicy.title(optionKeyIsPressed: usesForceQuitMenuItem)
    }
}

enum DockTerminationMenuPolicy {
    static func title(optionKeyIsPressed: Bool) -> String {
        optionKeyIsPressed ? "Force Quit..." : "Quit"
    }
}

enum DockContextMenuPolicy {
    // App-provided Dock menu entries are owned by the target process, not by
    // LaunchServices or NSWorkspace. A seemingly simple alternative would be to
    // special-case known apps such as Notion Calendar and add "Quit Completely"
    // ourselves, but that would guess at private app behavior and would age
    // badly when vendors rename, remove, or redefine their custom commands.
    // Keeping this false is a product contract: Docking shows the stable Dock
    // shape it can execute with public APIs, while app-specific extras remain
    // available from the real app/system surfaces that own them.
    static let includesAppProvidedDockMenuItems = false
}
