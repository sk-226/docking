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
    private var revealGate = AutoHideRevealGate()
    private var dockAutoHideResponsePreset: DockAutoHideResponsePreset = .standard
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
        dockAutoHideResponsePreset = settings.dockAutoHideResponsePreset
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
            revealGate.removeTarget(key)
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
        revealGate.reset()
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
        panel.contentView = EdgeTriggerView { [weak self] in
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handlePointerActivity(at: location)
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
        globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handlePointerActivity(at: location)
            }
        }
    }

    private func removeMouseMovedMonitors() {
        if let globalMouseMovedMonitor {
            NSEvent.removeMonitor(globalMouseMovedMonitor)
        }
        globalMouseMovedMonitor = nil
    }

    private func handlePointerActivity(at location: NSPoint) {
        guard let target = triggerTarget(containing: location) else {
            cancelPendingReveal()
            revealGate.update(targetKey: nil, requiresSecondPush: false, now: ProcessInfo.processInfo.systemUptime)
            onPointerOutsideTrigger?(location)
            return
        }

        onTriggerContact?(location)
        let decision = revealGate.update(
            targetKey: target.key,
            requiresSecondPush: target.requiresSecondPush,
            now: ProcessInfo.processInfo.systemUptime
        )
        guard let decision else {
            return
        }
        switch decision {
        case .ready:
            queueReveal(for: target)
        case .waitingForSecondPush:
            cancelPendingReveal()
        }
    }

    private func queueReveal(for target: EdgeTriggerTarget) {
        if pendingRevealKey == target.key {
            return
        }

        cancelPendingReveal()
        pendingRevealKey = target.key
        let delay = dockAutoHideResponsePreset.revealDelay
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
                  triggerTarget(containing: NSEvent.mouseLocation)?.key == target.key,
                  revealGate.currentTargetCanReveal(target.key) else {
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

            return EdgeTriggerTarget(
                key: key,
                screen: screen,
                requiresSecondPush: AutoHideTriggerGeometry.requiresSecondPush(
                    screenFrame: screenFrame,
                    visibleFrame: screen.visibleFrame,
                    position: dockPosition
                )
            )
        }
        return nil
    }

    private static func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        UInt64(seconds * 1_000_000_000)
    }

    nonisolated static func revealDelay(for settings: DockingSettings) -> TimeInterval {
        settings.dockAutoHideResponsePreset.revealDelay
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
    static let edgeActivationDistance: CGFloat = 1

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

    static func requiresSecondPush(screenFrame: NSRect, visibleFrame: NSRect, position: DockPosition) -> Bool {
        position.isBottom
            && abs(visibleFrame.minY - screenFrame.minY) < 1
            && abs(visibleFrame.maxY - screenFrame.maxY) < 1
    }
}

private struct EdgeTriggerTarget {
    let key: String
    let screen: NSScreen
    let requiresSecondPush: Bool
}

enum AutoHideRevealDecision: Equatable {
    case ready
    case waitingForSecondPush
}

struct AutoHideRevealGate {
    private static let secondPushWindow: TimeInterval = 1.25

    private var contactKey: String?
    private var contactCanReveal = false
    private var lastExitKey: String?
    private var lastExitTime: TimeInterval?

    @discardableResult
    mutating func update(targetKey: String?, requiresSecondPush: Bool, now: TimeInterval) -> AutoHideRevealDecision? {
        guard let targetKey else {
            if let contactKey {
                lastExitKey = contactKey
                lastExitTime = now
            }
            contactKey = nil
            contactCanReveal = false
            return nil
        }

        if contactKey != targetKey {
            contactKey = targetKey
            contactCanReveal = !requiresSecondPush || isSecondPush(for: targetKey, now: now)
        }

        return contactCanReveal ? .ready : .waitingForSecondPush
    }

    mutating func removeTarget(_ key: String) {
        if contactKey == key {
            contactKey = nil
            contactCanReveal = false
        }
        if lastExitKey == key {
            lastExitKey = nil
            lastExitTime = nil
        }
    }

    mutating func reset() {
        contactKey = nil
        contactCanReveal = false
        lastExitKey = nil
        lastExitTime = nil
    }

    func currentTargetCanReveal(_ key: String) -> Bool {
        contactKey == key && contactCanReveal
    }

    private func isSecondPush(for key: String, now: TimeInterval) -> Bool {
        lastExitKey == key
            && lastExitTime.map { now - $0 <= Self.secondPushWindow } == true
    }
}

private final class EdgeTriggerView: NSView {
    private let onPointerActivity: () -> Void

    init(onPointerActivity: @escaping () -> Void) {
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
        onPointerActivity()
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerActivity()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerActivity()
    }
}
