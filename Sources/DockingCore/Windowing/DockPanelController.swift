import AppKit
import SwiftUI

@MainActor
final class DockPanelController {
    private var panel: NSPanel?
    private let autoHideController = AutoHideController()

    var frame: NSRect? {
        panel?.frame
    }

    func show(model: DockingAppModel) {
        let panel = panel ?? makePanel(model: model)
        self.panel = panel
        applySettings(model.settings, itemCount: model.dockItems.count, widgetCount: model.enabledWidgetCount)
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

        let screen = ScreenPlacementService.dockScreen(for: settings)
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
        // Auto-hide changes whether the panel is ordered out, not whether it is
        // allowed to float. Dropping to .normal made the revealed Docking dock
        // appear behind ordinary app windows, which felt like auto-hide was
        // broken. The panel is still non-activating, so this does not turn the
        // dock into a foreground document window.
        panel.level = .floating
        panel.collectionBehavior = collectionBehavior(for: settings)

        autoHideController.update(settings: settings, dockFrame: frame, screen: screen) { [weak panel] in
            panel?.orderFrontRegardless()
        }
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
}
