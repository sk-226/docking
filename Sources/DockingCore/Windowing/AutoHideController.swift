import AppKit
import Foundation

@MainActor
final class AutoHideController {
    private var edgePanel: NSPanel?
    private var onEnter: (() -> Void)?

    func update(settings: DockingSettings, dockFrame: NSRect, screen: NSScreen?, onEnter: @escaping () -> Void) {
        self.onEnter = onEnter

        guard settings.dockVisibility == .autoHide else {
            edgePanel?.close()
            edgePanel = nil
            return
        }

        let frame = ScreenPlacementService.edgeTriggerFrame(dockFrame: dockFrame, position: settings.dockPosition, on: screen)
        let panel = edgePanel ?? makeEdgePanel()
        panel.setFrame(frame, display: true)
        panel.collectionBehavior = collectionBehavior(for: settings)
        panel.orderFrontRegardless()
        edgePanel = panel
    }

    func close() {
        edgePanel?.close()
        edgePanel = nil
    }

    private func makeEdgePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        // A tiny edge trigger panel avoids timer-based mouse polling. The panel
        // only exists when auto-hide is enabled and wakes the dock via tracking
        // area callbacks when the pointer reaches the screen edge.
        panel.contentView = EdgeTriggerView { [weak self] in
            self?.onEnter?()
        }
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

private final class EdgeTriggerView: NSView {
    private let onEnter: () -> Void

    init(onEnter: @escaping () -> Void) {
        self.onEnter = onEnter
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }

        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter()
    }
}
