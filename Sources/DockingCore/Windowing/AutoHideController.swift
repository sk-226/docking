import AppKit
import Foundation

@MainActor
final class AutoHideController {
    private var edgePanels: [String: NSPanel] = [:]
    private var edgePanelScreens: [String: NSScreen] = [:]
    private var edgePanelScreenFrames: [String: NSRect] = [:]
    private var triggerConfiguration: DockEdgeConfiguration?
    private var triggerEnvironment: [String: [NSRect]] = [:]
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var onEnter: ((NSScreen?) -> Void)?
    private var onTriggerContact: ((NSPoint) -> Void)?
    private var onPointerOutsideTrigger: ((NSPoint) -> Void)?
    private var pendingRevealTask: Task<Void, Never>?
    private var pendingRevealKey: String?
    private var revealGate = AutoHideRevealGate()
    private var edgeIntent = DockEdgeIntent()
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
        let separateSpaces = NSScreen.screensHaveSeparateSpaces
        let screens = Self.triggerScreens(
            for: settings, selectedScreen: screen, availableScreens: NSScreen.screens,
            screensHaveSeparateSpaces: separateSpaces
        )
        guard !screens.isEmpty else {
            close()
            return
        }

        let configuration = DockEdgeConfiguration(
            settings: settings,
            currentDisplayID: screen.flatMap { ScreenPlacementService.displayID(for: $0) },
            separateSpaces: separateSpaces
        )
        let environment = Dictionary(uniqueKeysWithValues: screens.map {
            (screenKey($0), [$0.frame, $0.visibleFrame])
        })
        if triggerConfiguration != configuration || triggerEnvironment != environment {
            // Settings, display removal and Space transitions invalidate queued
            // gestures; an ordinary app-icon refresh must not do so.
            cancelPendingReveal()
            revealGate.reset()
            edgeIntent.reset()
        }
        triggerConfiguration = configuration
        triggerEnvironment = environment
        self.onEnter = onEnter
        self.onTriggerContact = onTriggerContact
        self.onPointerOutsideTrigger = onPointerOutsideTrigger
        dockAutoHideResponsePreset = settings.dockAutoHideResponsePreset
        dockPosition = settings.dockPosition

        installEventMonitorsIfNeeded()

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
            let panel = edgePanels[key] ?? Self.makeEdgePanel()
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
        removeEventMonitors()
        for panel in edgePanels.values {
            panel.close()
        }
        edgePanels = [:]
        edgePanelScreens = [:]
        edgePanelScreenFrames = [:]
        triggerConfiguration = nil
        triggerEnvironment = [:]
        revealGate.reset()
        edgeIntent.reset()
        onEnter = nil
        onTriggerContact = nil
        onPointerOutsideTrigger = nil
    }

    static func makeEdgePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // These windows only locate targets and track their Space membership.
        // Input belongs to the underlying app, in both visibility modes.
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.contentView = NSView()
        return panel
    }

    // The injected flag describes the topology, independently of the test
    // machine's settings. Runtime callers pass NSScreen.screensHaveSeparateSpaces.
    nonisolated static func triggerScreens(
        for settings: DockingSettings,
        selectedScreen: NSScreen?,
        availableScreens: [NSScreen],
        screensHaveSeparateSpaces: Bool = true
    ) -> [NSScreen] {
        let screens = availableScreens.isEmpty ? selectedScreen.map { [$0] } ?? [] : availableScreens
        let ids = DockDisplayPolicy.triggerDisplayIDs(
            settings: settings,
            currentDisplayID: selectedScreen.flatMap { ScreenPlacementService.displayID(for: $0) },
            availableDisplayIDs: screens.compactMap { ScreenPlacementService.displayID(for: $0) },
            screensHaveSeparateSpaces: screensHaveSeparateSpaces
        )
        return screens.filter { screen in
            ScreenPlacementService.displayID(for: screen).map { ids.contains($0) } ?? false
        }
    }

    static let observedEvents: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseUp, .rightMouseUp, .otherMouseUp,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
    ]

    private func installEventMonitorsIfNeeded() {
        // Global monitors exclude our own windows; local monitors return the
        // original event so neither path consumes clicks, drags or scrolling.
        if globalEventMonitor == nil {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.observedEvents) { [weak self] event in
                MainActor.assumeIsolated { self?.handlePointerEvent(event) }
            }
        }
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.observedEvents) { [weak self] event in
                MainActor.assumeIsolated { self?.handlePointerEvent(event) }
                return event
            }
        }
    }

    private func removeEventMonitors() {
        if let globalEventMonitor { NSEvent.removeMonitor(globalEventMonitor) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        globalEventMonitor = nil
        localEventMonitor = nil
    }

    private func handlePointerEvent(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        guard event.type == .mouseMoved, NSEvent.pressedMouseButtons == 0 else {
            cancelPendingReveal()
            edgeIntent.reset()
            revealGate.reset()
            onPointerOutsideTrigger?(location)
            return
        }
        guard let target = triggerTarget(containing: location) else {
            cancelPendingReveal()
            edgeIntent.reset()
            revealGate.update(targetKey: nil, requiresSecondPush: false, now: event.timestamp)
            onPointerOutsideTrigger?(location)
            return
        }
        guard edgeIntent.update(targetKey: target.key, position: dockPosition, location: location,
                                delta: CGSize(width: event.deltaX, height: event.deltaY), now: event.timestamp) else {
            cancelPendingReveal()
            onPointerOutsideTrigger?(location)
            return
        }

        onTriggerContact?(location)
        let decision = revealGate.update(
            targetKey: target.key,
            requiresSecondPush: target.requiresSecondPush,
            now: event.timestamp
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
            guard !Task.isCancelled, NSEvent.pressedMouseButtons == 0,
                  pendingRevealKey == target.key,
                  edgeIntent.canReveal(targetKey: target.key, position: dockPosition, location: NSEvent.mouseLocation),
                  triggerTarget(containing: NSEvent.mouseLocation)?.key == target.key,
                  revealGate.currentTargetCanReveal(target.key) else {
                cancelPendingReveal()
                return
            }

            pendingRevealKey = nil
            pendingRevealTask = nil
            onEnter?(target.screen)
            edgeIntent.didReveal(targetKey: target.key)
        }
    }

    private func cancelPendingReveal() {
        pendingRevealTask?.cancel()
        pendingRevealTask = nil
        pendingRevealKey = nil
    }

    private func triggerTarget(containing location: NSPoint) -> EdgeTriggerTarget? {
        for (key, panel) in edgePanels {
            guard panel.isVisible, panel.isOnActiveSpace,
                  let screen = edgePanelScreens[key] else {
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
