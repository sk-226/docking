import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class DockPanelController: NSObject {
    private var panel: NSPanel?
    private let presentation = DockPresentation()
    private var layoutSettings = DockingSettings.default
    private var layoutItemCount = 0
    private var separatedRunningStart: Int?
    private var baseFrame = NSRect.zero
    private var maximumLength = Double.infinity
    private var contentFrame = NSRect.zero
    private var screenLimits = NSRect.zero
    private var pointerIsInside = false
    private var onPointerPresenceChange: ((Bool) -> Void)?
    private var pointerMonitors: [Any] = []
    private var displayLink: CADisplayLink?
    private var magnificationFrameState = DockMagnificationFrameState()
    private var targetMetrics = DockLayout.metrics(itemCount: 0, settings: .default)
    private let autoHideController = AutoHideController()
    private var currentDisplayID: UInt32?
    private var autoHideGeneration = 0
    private var isAutoHideScheduled = false
    private var dockPosition: DockPosition = .bottomCenter

    var frame: NSRect? {
        panel == nil ? nil : contentFrame
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show(model: DockingAppModel) {
        cancelScheduledAutoHide()
        let panel = panel ?? makePanel(model: model)
        self.panel = panel
        applySettings(model: model)
        panel.orderFrontRegardless()
        pointerMoved()
    }

    func hide() {
        cancelScheduledAutoHide()
        panel?.orderOut(nil)
        resetMagnification()
    }

    func orderFront() {
        cancelScheduledAutoHide()
        panel?.orderFrontRegardless()
    }

    func close() {
        cancelScheduledAutoHide()
        autoHideController.close()
        displayLink?.invalidate()
        displayLink = nil
        magnificationFrameState = DockMagnificationFrameState()
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors.removeAll()
        panel?.close()
        panel = nil
        currentDisplayID = nil
    }

    func applySettings(model: DockingAppModel) {
        guard let panel else {
            return
        }

        let settings = model.settings
        dockPosition = settings.dockPosition
        // Fixed settings always win. Automatic keeps its current connected
        // display across resizing, app updates and visibility changes.
        let screen = ScreenPlacementService.dockScreen(for: settings, currentDisplayID: currentDisplayID)
        currentDisplayID = screen.flatMap { ScreenPlacementService.displayID(for: $0) }
        configureLayout(model: model, screen: screen)
        panel.alphaValue = 1
        // The default is floating because Docking is meant to act like system
        // chrome, not a document. The toggle exists for workflows where a user
        // intentionally wants another always-on-top surface to win. We keep the
        // panel non-activating in both modes so changing this setting does not
        // turn Docking into a focus-stealing app window.
        panel.isFloatingPanel = settings.keepAboveOtherWindows
        panel.level = Self.windowLevel(for: settings)
        panel.collectionBehavior = DockingWindowBehavior.collectionBehavior(for: settings)

        autoHideController.update(
            settings: settings,
            dockFrame: baseFrame,
            screen: screen,
            onEnter: { [weak self, weak model] screen in
                guard let model else {
                    return
                }
                self?.reveal(on: screen, model: model)
            },
            onTriggerContact: { [weak model] _ in
                model?.pointerContactedAutoHideTrigger()
            },
            onPointerOutsideTrigger: { [weak model] location in
                model?.scheduleAutoHideIfNeeded(pointerLocation: location)
            }
        )
    }

    private func reveal(on screen: NSScreen?, model: DockingAppModel) {
        guard let panel, let screen,
              let id = ScreenPlacementService.displayID(for: screen) else { return }
        // A delayed edge callback must not override a newer fixed-display or
        // Spaces setting, even if the display is still physically connected.
        let eligible = DockDisplayPolicy.triggerDisplayIDs(
            settings: model.settings, currentDisplayID: currentDisplayID,
            availableDisplayIDs: NSScreen.screens.compactMap { ScreenPlacementService.displayID(for: $0) },
            screensHaveSeparateSpaces: NSScreen.screensHaveSeparateSpaces
        )
        guard eligible.contains(id) else { return }
        currentDisplayID = id
        applySettings(model: model)
        cancelScheduledAutoHide()
        if !panel.isVisible { panel.orderFrontRegardless() }
        pointerMoved()
    }

    private func configureLayout(model: DockingAppModel, screen: NSScreen?) {
        let settings = model.settings
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let newScreenLimits = visibleFrame.insetBy(dx: ScreenPlacementService.dockScreenMargin, dy: ScreenPlacementService.dockScreenMargin)
        let screenChanged = screenLimits != newScreenLimits
        screenLimits = newScreenLimits
        let length = settings.dockPosition.isVertical ? screenLimits.height : screenLimits.width
        let runningStart = model.hasSeparatedRunningItems ? model.displayDockItems.count : nil
        let changed = screenChanged || layoutSettings != settings || layoutItemCount != model.visibleAppItemCount || separatedRunningStart != runningStart || maximumLength != length
        layoutSettings = settings
        layoutItemCount = model.visibleAppItemCount
        separatedRunningStart = runningStart
        maximumLength = length
        let frameRate = Float(screen?.maximumFramesPerSecond ?? 60)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, frameRate), maximum: frameRate, preferred: frameRate)
        let resting = layoutMetrics()
        baseFrame = ScreenPlacementService.dockFrame(size: resting.scaledPanelSize, on: screen, position: settings.dockPosition)
        let canvas = DockPanelGeometry.canvasFrame(baseFrame: baseFrame, resting: resting,
                                                  settings: settings, limits: screenLimits)
        if let panel, !Self.framesApproximatelyEqual(panel.frame, canvas) {
            panel.setFrame(canvas, display: true, animate: false)
        }
        if changed || presentation.metrics.iconSizes.count != layoutItemCount {
            resetMagnification()
        } else {
            applyGeometry(presentation.metrics)
        }
    }

    private func layoutMetrics(pointer: Double? = nil, bounds: DockMagnificationBounds = DockMagnificationBounds()) -> DockLayoutMetrics {
        var settings = layoutSettings
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { settings.magnificationEnabled = false }
        return DockLayout.metrics(itemCount: layoutItemCount, settings: settings,
                                  separatedRunningStart: separatedRunningStart, maximumLength: maximumLength,
                                  pointerOffset: pointer, magnificationBounds: bounds)
    }

    private func resetMagnification() {
        displayLink?.isPaused = true
        magnificationFrameState = DockMagnificationFrameState()
        targetMetrics = layoutMetrics()
        applyGeometry(targetMetrics)
    }

    private func pointerMoved() {
        guard let panel, panel.isVisible else { return }
        let location = NSEvent.mouseLocation
        let inside = DockPanelHitGeometry.contains(location, panelFrame: contentFrame, position: dockPosition)
        let offset = dockPosition.isVertical ? baseFrame.maxY - location.y : location.x - baseFrame.minX
        let magnifies = layoutSettings.magnificationEnabled && layoutItemCount > 0
            && layoutSettings.magnificationSize > layoutSettings.iconSize
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let requestedOffset = inside && magnifies ? offset / presentation.metrics.scale : nil
        let targetChanged = magnificationFrameState.request(pointerOffset: requestedOffset)
        updateMousePassthrough(at: location)
        if targetChanged, displayLink?.isPaused == true {
            magnificationFrameState.resetClock()
            displayLink?.isPaused = false
        }
        if pointerIsInside != inside {
            pointerIsInside = inside
            onPointerPresenceChange?(inside)
        }
    }

    @objc private func stepMagnification(_ link: CADisplayLink) {
        guard panel?.isVisible == true else {
            link.isPaused = true
            magnificationFrameState.resetClock()
            return
        }
        pointerMoved()
        if let update = magnificationFrameState.takeTargetUpdate() {
            let bounds = DockPanelGeometry.magnificationBounds(baseFrame: baseFrame, position: dockPosition,
                                                              limits: screenLimits, scale: presentation.metrics.scale)
            targetMetrics = layoutMetrics(pointer: update.pointerOffset, bounds: bounds)
        }
        let elapsed = magnificationFrameState.elapsedTime(timestamp: link.timestamp, targetTimestamp: link.targetTimestamp)
        applyGeometry(presentation.metrics.approaching(targetMetrics, elapsed: elapsed))
        if presentation.metrics == targetMetrics {
            link.isPaused = true
            magnificationFrameState.resetClock()
        }
    }

    private func updateMousePassthrough(at location: NSPoint) {
        guard let panel else { return }
        let ignoresMouseEvents = !contentFrame.contains(location)
        if panel.ignoresMouseEvents != ignoresMouseEvents {
            panel.ignoresMouseEvents = ignoresMouseEvents
        }
    }

    private func applyGeometry(_ metrics: DockLayoutMetrics) {
        guard let panel else { return }
        contentFrame = DockPanelGeometry.contentFrame(baseFrame: baseFrame, metrics: metrics,
                                                      position: dockPosition, limits: screenLimits)
        let layout = DockPresentationLayout(
            metrics: metrics,
            origin: CGPoint(x: contentFrame.minX - panel.frame.minX, y: panel.frame.maxY - contentFrame.maxY),
            canvasSize: panel.frame.size
        )
        if presentation.layout != layout { presentation.layout = layout }
        updateMousePassthrough(at: NSEvent.mouseLocation)
    }

    func scheduleAutoHide(model: DockingAppModel) {
        guard model.shouldScheduleAutoHide(pointerLocation: NSEvent.mouseLocation),
              !isAutoHideScheduled else {
            return
        }

        isAutoHideScheduled = true
        autoHideGeneration += 1
        let generation = autoHideGeneration
        let delay = model.settings.autoHideDelay
        Task { @MainActor [weak self, weak model] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.autoHideGeneration == generation else {
                return
            }
            self.isAutoHideScheduled = false
            guard let model,
                  model.shouldScheduleAutoHide(pointerLocation: NSEvent.mouseLocation) else {
                return
            }
            self.hide()
        }
    }

    func cancelScheduledAutoHide() {
        guard isAutoHideScheduled else {
            return
        }
        autoHideGeneration += 1
        isAutoHideScheduled = false
    }

    func containsPointer(at location: NSPoint) -> Bool {
        guard let panel, panel.isVisible else {
            return false
        }
        return DockPanelHitGeometry.contains(location, panelFrame: contentFrame, position: dockPosition)
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
        onPointerPresenceChange = { [weak model] inside in
            if inside { model?.pointerEnteredDock() }
            else { model?.pointerExitedDock() }
        }
        let hostingView = NSHostingView(rootView: DockView(presentation: presentation).environmentObject(model))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.acceptsMouseMovedEvents = true
        let link = panel.displayLink(target: self, selector: #selector(stepMagnification(_:)))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) { pointerMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { pointerMonitors.append(monitor) }
        return panel
    }

    nonisolated static func windowLevel(for settings: DockingSettings) -> NSWindow.Level {
        settings.keepAboveOtherWindows ? .floating : .normal
    }

    private static func framesApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5
            && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }
}

enum DockPanelGeometry {
    static func magnificationBounds(baseFrame: NSRect, position: DockPosition, limits: NSRect, scale: Double) -> DockMagnificationBounds {
        if position.isVertical {
            return DockMagnificationBounds(leading: max(0, limits.maxY - baseFrame.maxY) / scale,
                                           trailing: max(0, baseFrame.minY - limits.minY) / scale)
        }
        return DockMagnificationBounds(leading: max(0, baseFrame.minX - limits.minX) / scale,
                                       trailing: max(0, limits.maxX - baseFrame.maxX) / scale)
    }

    static func contentFrame(baseFrame: NSRect, metrics: DockLayoutMetrics, position: DockPosition, limits: NSRect) -> NSRect {
        var frame = NSRect(origin: baseFrame.origin, size: metrics.scaledPanelSize)
        if position.isVertical {
            frame.origin.y = baseFrame.maxY - frame.height + metrics.originShift * metrics.scale
            if position == .right { frame.origin.x = baseFrame.maxX - frame.width }
        } else {
            frame.origin.x -= metrics.originShift * metrics.scale
        }
        frame.origin.x = min(max(frame.minX, limits.minX), limits.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, limits.minY), limits.maxY - frame.height)
        return frame
    }

    static func canvasFrame(baseFrame: NSRect, resting: DockLayoutMetrics, settings: DockingSettings, limits: NSRect) -> NSRect {
        let extra = settings.magnificationEnabled && !resting.iconSizes.isEmpty
            ? max(0, settings.magnificationSize - settings.iconSize) * resting.scale : 0
        let growth = Double(min(resting.iconSizes.count, 4)) * extra
        var frame = baseFrame
        if settings.dockPosition.isVertical {
            frame = frame.insetBy(dx: 0, dy: -growth)
            frame.size.width += extra
            if settings.dockPosition == .right { frame.origin.x -= extra }
        } else {
            frame = frame.insetBy(dx: -growth, dy: 0)
            frame.size.height += extra
        }
        return frame.intersection(limits)
    }
}

enum DockPanelHitGeometry {
    static func contains(_ location: NSPoint, panelFrame: NSRect, position: DockPosition) -> Bool {
        residenceFrame(for: panelFrame, position: position).contains(location)
    }

    private static func residenceFrame(for panelFrame: NSRect, position: DockPosition) -> NSRect {
        var frame = panelFrame
        switch position {
        case .bottomCenter, .bottomLeft, .bottomRight:
            frame.origin.y -= ScreenPlacementService.dockScreenMargin
            frame.size.height += ScreenPlacementService.dockScreenMargin
        case .left:
            frame.origin.x -= ScreenPlacementService.dockScreenMargin
            frame.size.width += ScreenPlacementService.dockScreenMargin
        case .right:
            frame.size.width += ScreenPlacementService.dockScreenMargin
        }
        return frame
    }
}
