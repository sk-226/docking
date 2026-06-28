import AppKit
import Foundation

@MainActor
final class AutoHideController {
    private var edgePanels: [String: NSPanel] = [:]
    private var edgePanelScreens: [String: NSScreen] = [:]
    private var globalMouseMovedMonitor: Any?
    private var onEnter: ((NSScreen?) -> Void)?

    func update(settings: DockingSettings, dockFrame: NSRect, screen: NSScreen?, onEnter: @escaping (NSScreen?) -> Void) {
        self.onEnter = onEnter

        guard settings.dockVisibility == .autoHide else {
            close()
            return
        }

        installMouseMovedMonitorsIfNeeded()

        let screens = Self.triggerScreens(for: settings, selectedScreen: screen, availableScreens: NSScreen.screens)
        let wantedKeys = Set(screens.map(screenKey))
        for (key, panel) in edgePanels where !wantedKeys.contains(key) {
            panel.close()
            edgePanels[key] = nil
            edgePanelScreens[key] = nil
        }

        for triggerScreen in screens {
            let key = screenKey(triggerScreen)
            let screenDockFrame = ScreenPlacementService.dockFrame(size: dockFrame.size, on: triggerScreen, position: settings.dockPosition)
            let frame = ScreenPlacementService.edgeTriggerFrame(
                dockFrame: screenDockFrame,
                position: settings.dockPosition,
                on: triggerScreen,
                spansFullBottomEdge: settings.dockPosition.isBottom
            )
            let panel = edgePanels[key] ?? makeEdgePanel(for: triggerScreen)
            panel.setFrame(frame, display: true)
            panel.collectionBehavior = DockingWindowBehavior.collectionBehavior(for: settings)
            panel.orderFrontRegardless()
            edgePanels[key] = panel
            edgePanelScreens[key] = triggerScreen
        }
    }

    func close() {
        removeMouseMovedMonitors()
        for panel in edgePanels.values {
            panel.close()
        }
        edgePanels = [:]
        edgePanelScreens = [:]
    }

    private func makeEdgePanel(for screen: NSScreen?) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        // The edge strip is a transparent, non-activating panel, and some
        // pointer paths only deliver movement inside the strip rather than a
        // clean entered/exited transition. Accepting moved events keeps reveal
        // tied to real edge interaction without falling back to a timer polling
        // loop, which would be worse for idle battery life in a resident dock
        // app.
        panel.acceptsMouseMovedEvents = true
        panel.level = .statusBar
        // Tiny edge trigger panels avoid timer-based mouse polling. Bottom
        // docks get one trigger per display so the Docking dock can appear on
        // whichever screen edge the user pushes into, matching the expectation
        // set by Apple's Dock on multi-display systems.
        panel.contentView = EdgeTriggerView { [weak self] in
            self?.onEnter?(screen)
        }
        return panel
    }

    nonisolated static func triggerScreens(for settings: DockingSettings, selectedScreen: NSScreen?, availableScreens: [NSScreen]) -> [NSScreen] {
        if settings.dockPosition.isBottom {
            // Bottom auto-hide is the one mode where selected-display behavior
            // is intentionally overridden. Apple's Dock can be revealed from
            // the bottom edge of any attached display, and users expect the
            // same muscle memory here. A single selected-screen trigger looked
            // simpler, but it made the Docking dock feel broken as soon as the
            // pointer was on another monitor. Non-bottom docks stay scoped to
            // one display because full-height left/right trigger strips on
            // every monitor would be much more likely to intercept unrelated
            // edge gestures.
            return availableScreens.isEmpty ? selectedScreen.map { [$0] } ?? [] : availableScreens
        }
        return selectedScreen.map { [$0] } ?? availableScreens.prefix(1).map { $0 }
    }

    private func installMouseMovedMonitorsIfNeeded() {
        guard globalMouseMovedMonitor == nil else {
            return
        }

        // The transparent trigger panel is still the primary hit target, but
        // WindowServer/AppKit can miss tracking-area transitions on some edge
        // paths while another app owns the frontmost event stream. A global
        // monitor gives us that second event-driven path without adding a timer
        // or duplicating events already delivered to `EdgeTriggerView`. We keep
        // the work intentionally tiny: compare the current location against the
        // existing edge-panel frames, then reveal on the matching display.
        globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.revealIfLocationIsInsideEdgeTrigger(location)
            }
        }
    }

    private func removeMouseMovedMonitors() {
        if let globalMouseMovedMonitor {
            NSEvent.removeMonitor(globalMouseMovedMonitor)
        }
        globalMouseMovedMonitor = nil
    }

    private func revealIfLocationIsInsideEdgeTrigger(_ location: NSPoint) {
        for (key, panel) in edgePanels {
            guard panel.frame.insetBy(dx: -2, dy: -2).contains(location) else {
                continue
            }

            onEnter?(edgePanelScreens[key])
            return
        }
    }

    private func screenKey(_ screen: NSScreen?) -> String {
        guard let screen else {
            return "fallback"
        }
        let frame = screen.frame
        return "\(screen.localizedName)-\(Int(frame.minX))-\(Int(frame.minY))-\(Int(frame.width))-\(Int(frame.height))"
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
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter()
    }

    override func mouseMoved(with event: NSEvent) {
        // Do not debounce this with an "inside" flag. The trigger panel is only
        // eight points tall and receives events only while the pointer is on the
        // physical edge; repeating a cheap `orderFront` during edge movement is
        // less fragile than remembering stale inside/outside state across
        // hidden-panel cycles and display changes.
        onEnter()
    }
}
