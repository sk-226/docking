import AppKit
import Foundation

@MainActor
final class AutoHideController {
    private var edgePanels: [String: NSPanel] = [:]
    private var edgePanelScreens: [String: NSScreen] = [:]
    private var edgePanelScreenFrames: [String: NSRect] = [:]
    private var globalMouseMovedMonitor: Any?
    private var onEnter: ((NSScreen?) -> Void)?
    private var onTriggerContact: ((NSPoint) -> Void)?
    private var onPointerOutsideTrigger: ((NSPoint) -> Void)?
    private var pendingRevealTask: Task<Void, Never>?
    private var pendingRevealKey: String?
    private var dockPosition: DockPosition = .bottomCenter

    func update(
        settings: DockingSettings,
        dockFrame: NSRect,
        screen: NSScreen?,
        onEnter: @escaping (NSScreen?) -> Void,
        onTriggerContact: @escaping (NSPoint) -> Void,
        onPointerOutsideTrigger: @escaping (NSPoint) -> Void
    ) {
        self.onEnter = onEnter
        self.onTriggerContact = onTriggerContact
        self.onPointerOutsideTrigger = onPointerOutsideTrigger
        dockPosition = settings.dockPosition

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
            edgePanelScreenFrames[key] = nil
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
            let panel = edgePanels[key] ?? makeEdgePanel()
            panel.setFrame(frame, display: true)
            panel.collectionBehavior = DockingWindowBehavior.collectionBehavior(for: settings)
            panel.orderFrontRegardless()
            edgePanels[key] = panel
            edgePanelScreens[key] = triggerScreen
            edgePanelScreenFrames[key] = triggerScreen.frame
        }
    }

    func close() {
        cancelPendingReveal()
        removeMouseMovedMonitors()
        for panel in edgePanels.values {
            panel.close()
        }
        edgePanels = [:]
        edgePanelScreens = [:]
        edgePanelScreenFrames = [:]
        onEnter = nil
        onTriggerContact = nil
        onPointerOutsideTrigger = nil
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
        panel.contentView = EdgeTriggerView { [weak self] eventKind in
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handlePointerActivity(at: location, eventKind: eventKind)
            }
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
        globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            let location = NSEvent.mouseLocation
            let eventKind: EdgeTriggerEventKind = event.type == .leftMouseDragged ? .drag : .move
            Task { @MainActor in
                self?.handlePointerActivity(at: location, eventKind: eventKind)
            }
        }
    }

    private func removeMouseMovedMonitors() {
        if let globalMouseMovedMonitor {
            NSEvent.removeMonitor(globalMouseMovedMonitor)
        }
        globalMouseMovedMonitor = nil
    }

    private func handlePointerActivity(at location: NSPoint, eventKind: EdgeTriggerEventKind) {
        guard let target = triggerTarget(containing: location) else {
            cancelPendingReveal()
            onPointerOutsideTrigger?(location)
            return
        }

        onTriggerContact?(location)
        queueReveal(for: target, eventKind: eventKind)
    }

    private func queueReveal(for target: EdgeTriggerTarget, eventKind: EdgeTriggerEventKind) {
        if pendingRevealKey == target.key {
            return
        }

        cancelPendingReveal()
        pendingRevealKey = target.key
        let delay = eventKind == .drag
            ? AutoHideTriggerGeometry.dragRevealDelay
            : AutoHideTriggerGeometry.revealDelay
        pendingRevealTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
            } catch {
                return
            }
            guard let self else {
                return
            }
            guard pendingRevealKey == target.key,
                  triggerTarget(containing: NSEvent.mouseLocation)?.key == target.key else {
                cancelPendingReveal()
                return
            }

            pendingRevealKey = nil
            pendingRevealTask = nil
            onEnter?(target.screen)
        }
    }

    private func cancelPendingReveal() {
        pendingRevealTask?.cancel()
        pendingRevealTask = nil
        pendingRevealKey = nil
    }

    private func triggerTarget(containing location: NSPoint) -> EdgeTriggerTarget? {
        for (key, panel) in edgePanels {
            guard let screen = edgePanelScreens[key] else {
                continue
            }
            let screenFrame = edgePanelScreenFrames[key] ?? screen.frame
            guard AutoHideTriggerGeometry.containsEdgeContact(
                location,
                triggerFrame: panel.frame,
                screenFrame: screenFrame,
                position: dockPosition
            ) else {
                continue
            }

            return EdgeTriggerTarget(key: key, screen: screen)
        }
        return nil
    }

    private static func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        UInt64(seconds * 1_000_000_000)
    }

    private func screenKey(_ screen: NSScreen?) -> String {
        guard let screen else {
            return "fallback"
        }
        if let displayID = ScreenPlacementService.displayID(for: screen) {
            return "display-\(displayID)"
        }
        let frame = screen.frame
        return "\(screen.localizedName)-\(Int(frame.minX))-\(Int(frame.minY))-\(Int(frame.width))-\(Int(frame.height))"
    }

}

enum AutoHideTriggerGeometry {
    static let panelThickness: CGFloat = 8
    static let edgeActivationDistance: CGFloat = 2
    static let revealDelay: TimeInterval = 0.5
    static let dragRevealDelay: TimeInterval = 0.5

    static func containsEdgeContact(
        _ location: NSPoint,
        triggerFrame: NSRect,
        screenFrame: NSRect,
        position: DockPosition
    ) -> Bool {
        switch position {
        case .bottomCenter, .bottomLeft, .bottomRight:
            return location.x >= triggerFrame.minX
                && location.x <= triggerFrame.maxX
                && location.y >= screenFrame.minY
                && location.y <= screenFrame.minY + edgeActivationDistance
        case .left:
            return location.y >= triggerFrame.minY
                && location.y <= triggerFrame.maxY
                && location.x >= screenFrame.minX
                && location.x <= screenFrame.minX + edgeActivationDistance
        case .right:
            return location.y >= triggerFrame.minY
                && location.y <= triggerFrame.maxY
                && location.x >= screenFrame.maxX - edgeActivationDistance
                && location.x <= screenFrame.maxX
        }
    }
}

private struct EdgeTriggerTarget {
    let key: String
    let screen: NSScreen
}

private enum EdgeTriggerEventKind {
    case move
    case drag
}

private final class EdgeTriggerView: NSView {
    private let onPointerActivity: (EdgeTriggerEventKind) -> Void

    init(onPointerActivity: @escaping (EdgeTriggerEventKind) -> Void) {
        self.onPointerActivity = onPointerActivity
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
        onPointerActivity(.move)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerActivity(.move)
    }

    override func mouseDragged(with event: NSEvent) {
        onPointerActivity(.drag)
    }
}
