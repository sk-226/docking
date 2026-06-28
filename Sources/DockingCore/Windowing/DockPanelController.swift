import AppKit
import SwiftUI

@MainActor
final class DockPanelController {
    private var panel: NSPanel?
    private let autoHideController = AutoHideController()
    private var revealScreen: NSScreen?

    var frame: NSRect? {
        panel?.frame
    }

    func show(model: DockingAppModel) {
        let panel = panel ?? makePanel(model: model)
        self.panel = panel
        // Manual "Show Dock" must size the panel from the same visible model as
        // auto-hide reveals. Using only pinned items looked fine before
        // transient running apps existed, but would clip the separated running
        // section exactly when a user was trying to inspect it.
        applySettings(model.settings, itemCount: model.visibleAppItemCount, widgetCount: model.enabledWidgetCount)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func orderFront() {
        panel?.orderFrontRegardless()
    }

    func close() {
        autoHideController.close()
        panel?.close()
        panel = nil
    }

    func applySettings(_ settings: DockingSettings, itemCount: Int, widgetCount: Int) {
        guard let panel else {
            return
        }

        if settings.dockVisibility != .autoHide || !settings.dockPosition.isBottom {
            revealScreen = nil
        }

        let screen = revealScreen ?? ScreenPlacementService.dockScreen(for: settings)
        let size = DockLayout.panelSize(itemCount: itemCount, widgetCount: widgetCount, settings: settings)
        let frame = ScreenPlacementService.dockFrame(size: size, on: screen, position: settings.dockPosition)
        // Avoid AppKit's window-frame animation here. The dock frame is often
        // applied while SwiftUI is still laying out the hosting view during
        // launch, Space changes, or live settings updates; asking AppKit to
        // animate the same transaction can trigger layout recursion warnings.
        // Docking's visible motion comes from lightweight SwiftUI hover/detail
        // transitions, not from resizing the resident panel itself.
        panel.setFrame(frame, display: true, animate: false)
        panel.alphaValue = settings.opacity
        // The default is floating because Docking is meant to act like system
        // chrome, not a document. The toggle exists for workflows where a user
        // intentionally wants another always-on-top surface to win. We keep the
        // panel non-activating in both modes so changing this setting does not
        // turn Docking into a focus-stealing app window.
        panel.isFloatingPanel = settings.keepAboveOtherWindows
        panel.level = Self.windowLevel(for: settings)
        panel.collectionBehavior = collectionBehavior(for: settings)

        autoHideController.update(settings: settings, dockFrame: frame, screen: screen) { [weak self] screen in
            self?.reveal(on: screen, settings: settings, itemCount: itemCount, widgetCount: widgetCount)
        }
    }

    private func reveal(on screen: NSScreen?, settings: DockingSettings, itemCount: Int, widgetCount: Int) {
        guard let panel else {
            return
        }

        revealScreen = screen
        let size = DockLayout.panelSize(itemCount: itemCount, widgetCount: widgetCount, settings: settings)
        let frame = ScreenPlacementService.dockFrame(size: size, on: screen ?? ScreenPlacementService.dockScreen(for: settings), position: settings.dockPosition)
        panel.setFrame(frame, display: true, animate: false)
        panel.orderFrontRegardless()
    }

    func scheduleAutoHide(model: DockingAppModel) {
        guard model.settings.dockVisibility == .autoHide else {
            return
        }

        let delay = model.settings.autoHideDelay
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard model.settings.dockVisibility == .autoHide, !model.isPointerInsideDock else {
                return
            }
            self?.hide()
        }
    }

    private func makePanel(model: DockingAppModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Docking Dock"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        // The dock should feel like system chrome rather than an app document.
        // A non-activating panel lets clicks launch apps and open widgets without
        // stealing focus from the user's current workspace.
        panel.contentView = NSHostingView(rootView: DockView().environmentObject(model))
        return panel
    }

    private func collectionBehavior(for settings: DockingSettings) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.transient, .ignoresCycle]
        if settings.showOnAllSpaces {
            behavior.insert(.canJoinAllSpaces)
        }
        if settings.showOnFullScreenSpaces {
            behavior.insert(.fullScreenAuxiliary)
        }
        return behavior
    }

    nonisolated static func windowLevel(for settings: DockingSettings) -> NSWindow.Level {
        settings.keepAboveOtherWindows ? .floating : .normal
    }
}
