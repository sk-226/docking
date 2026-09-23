import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class DockPanelController: NSObject {
    private var panel: NSPanel?
    private let presentation = DockPresentation()
    private var layoutSettings = DockingSettings.default
    private var layoutItemCount = 0
    private var documentStart: Int?
    private var runningSectionStart: Int?
    private var baseFrame = NSRect.zero
    private var canvasFrame = NSRect.zero
    private var visibilityAnimation = DockAutoHideAnimation()
    private var maximumLength = Double.infinity
    private var contentFrame = NSRect.zero
    private var residenceFrame = NSRect.zero
    private var screenLimits = NSRect.zero
    private var pointerIsInside = false
    private var isMenuTracking = false
    private var isItemDragging = false
    private let windowEventRegion = DockWindowEventRegion()
    private var hasWindowEventRegion = false
    private var onPointerPresenceChange: ((Bool) -> Void)?
    private var pointerMonitors: [Any] = []
    private var displayLink: CADisplayLink?
    private var magnificationFrameState = DockMagnificationFrameState()
    private var magnificationAnimation = DockMagnificationAnimation()
    private var magnificationPointer: Double?
    private var launchAnimations: [UUID: DockLaunchAnimation] = [:]
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
        visibilityAnimation = DockAutoHideAnimation()
        applySettings(model: model)
        panel.orderFrontRegardless()
        pointerMoved()
    }

    func hide() {
        cancelScheduledAutoHide()
        panel?.orderOut(nil)
        visibilityAnimation = DockAutoHideAnimation(hidden: true)
        pointerIsInside = false
        launchAnimations.removeAll()
        resetMagnification()
    }

    func orderFront() {
        cancelScheduledAutoHide()
        visibilityAnimation = DockAutoHideAnimation()
        applyGeometry(presentation.metrics)
        panel?.orderFrontRegardless()
        pointerMoved()
    }

    func startLaunchAnimation(for itemID: UUID) {
        guard isVisible, launchAnimations[itemID] == nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        launchAnimations[itemID] = DockLaunchAnimation()
        resumeDisplayLink()
    }

    func finishLaunchAnimation(for itemID: UUID) {
        launchAnimations[itemID]?.finish()
    }

    private func resumeDisplayLink() {
        guard displayLink?.isPaused == true else { return }
        magnificationFrameState.resetClock()
        displayLink?.isPaused = false
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
        if !panel.isVisible {
            visibilityAnimation = DockAutoHideAnimation(hidden: true)
            applyGeometry(presentation.metrics)
            panel.orderFrontRegardless()
        }
        animateVisibility(hidden: false)
        pointerMoved()
    }

    private func configureLayout(model: DockingAppModel, screen: NSScreen?) {
        let settings = model.settings
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let newScreenLimits = visibleFrame.insetBy(dx: ScreenPlacementService.dockScreenMargin, dy: ScreenPlacementService.dockScreenMargin)
        let screenChanged = screenLimits != newScreenLimits
        screenLimits = newScreenLimits
        let length = settings.dockPosition.isVertical ? screenLimits.height : screenLimits.width
        let documentStart = model.documentStart
        let changed = screenChanged || layoutSettings != settings || layoutItemCount != model.visibleDockItems.count || self.documentStart != documentStart || runningSectionStart != model.runningSectionStart || maximumLength != length
        layoutSettings = settings
        layoutItemCount = model.visibleDockItems.count
        self.documentStart = documentStart
        runningSectionStart = model.runningSectionStart
        maximumLength = length
        let frameRate = Float(screen?.maximumFramesPerSecond ?? 60)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, frameRate), maximum: frameRate, preferred: frameRate)
        let resting = layoutMetrics()
        baseFrame = ScreenPlacementService.dockFrame(size: resting.scaledPanelSize, on: screen, position: settings.dockPosition)
        let canvas = DockPanelGeometry.canvasFrame(baseFrame: baseFrame, resting: resting,
                                                  settings: settings, limits: screenLimits)
        canvasFrame = canvas
        if changed || presentation.metrics.iconSizes.count != layoutItemCount {
            resetMagnification()
        } else {
            applyGeometry(presentation.metrics)
        }
    }

    private func layoutMetrics(pointer: Double? = nil, progress: Double = 1,
                               bounds: DockMagnificationBounds = DockMagnificationBounds()) -> DockLayoutMetrics {
        var settings = layoutSettings
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { settings.magnificationEnabled = false }
        return DockLayout.metrics(itemCount: layoutItemCount, settings: settings,
                                  documentStart: documentStart, runningSectionStart: runningSectionStart, maximumLength: maximumLength,
                                  pointerOffset: pointer, magnificationProgress: progress, magnificationBounds: bounds)
    }

    private func resetMagnification() {
        displayLink?.isPaused = true
        magnificationFrameState = DockMagnificationFrameState()
        magnificationAnimation = DockMagnificationAnimation()
        magnificationPointer = nil
        applyGeometry(layoutMetrics())
        if visibilityAnimation.isAnimating || !launchAnimations.isEmpty { resumeDisplayLink() }
    }

    func setMenuTracking(_ tracking: Bool) {
        isMenuTracking = tracking
        if !tracking {
            pointerMoved()
            if magnificationAnimation.isAnimating || magnificationFrameState.hasPendingTarget { resumeDisplayLink() }
        }
    }

    func setItemDragging(_ dragging: Bool) {
        isItemDragging = dragging
        if !dragging {
            pointerMoved()
            if magnificationAnimation.isAnimating || magnificationFrameState.hasPendingTarget { resumeDisplayLink() }
        }
    }

    func trackDrag(at location: CGPoint) {
        pointerMoved(at: location)
        guard !isMenuTracking, let update = magnificationFrameState.takeTargetUpdate() else { return }
        if let offset = update.pointerOffset { magnificationPointer = offset }
        magnificationAnimation.setActive(update.pointerOffset != nil,
                                         maximumGrowth: layoutSettings.magnificationSize - layoutSettings.iconSize)
        let bounds = DockPanelGeometry.magnificationBounds(baseFrame: baseFrame, position: dockPosition,
                                                          limits: screenLimits, scale: presentation.metrics.scale)
        applyGeometry(layoutMetrics(pointer: magnificationPointer, progress: magnificationAnimation.value, bounds: bounds))
    }

    func itemFrames(for items: [DockItem]) -> [UUID: CGRect] {
        DockDragGeometry.frames(items: items, metrics: presentation.metrics, contentFrame: contentFrame, settings: layoutSettings)
    }

    private func pointerMoved(at location: CGPoint = NSEvent.mouseLocation) {
        guard let panel, panel.isVisible, !isMenuTracking else { return }
        let inside = residenceFrame.contains(location)
        let offset = dockPosition.isVertical ? baseFrame.maxY - location.y : location.x - baseFrame.minX
        let magnifies = layoutSettings.magnificationEnabled && layoutItemCount > 0
            && layoutSettings.magnificationSize > layoutSettings.iconSize
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let requestedOffset = inside && magnifies ? offset / presentation.metrics.scale : nil
        let targetChanged = magnificationFrameState.request(pointerOffset: requestedOffset, at: CACurrentMediaTime())
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
        let holdsMagnification = isMenuTracking
        let hasInput = !holdsMagnification && magnificationFrameState.hasPendingTarget
        let needsGeometry = hasInput || (!holdsMagnification && magnificationAnimation.isAnimating)
            || visibilityAnimation.isAnimating || !launchAnimations.isEmpty
        if !holdsMagnification, let update = magnificationFrameState.takeTargetUpdate() {
            if let offset = update.pointerOffset { magnificationPointer = offset }
            magnificationAnimation.setActive(update.pointerOffset != nil,
                                             maximumGrowth: layoutSettings.magnificationSize - layoutSettings.iconSize)
        }
        let elapsed = magnificationFrameState.elapsedTime(timestamp: link.timestamp, targetTimestamp: link.targetTimestamp, currentTime: CACurrentMediaTime())
        let progress = holdsMagnification ? magnificationAnimation.value : magnificationAnimation.advance(by: elapsed)
        visibilityAnimation.advance(by: elapsed)
        for itemID in launchAnimations.keys { launchAnimations[itemID]?.advance(by: elapsed) }
        launchAnimations = launchAnimations.filter { $0.value.isAnimating }
        let bounds = DockPanelGeometry.magnificationBounds(baseFrame: baseFrame, position: dockPosition,
                                                          limits: screenLimits, scale: presentation.metrics.scale)
        if needsGeometry {
            applyGeometry(holdsMagnification ? presentation.metrics : layoutMetrics(pointer: magnificationPointer, progress: progress, bounds: bounds))
        }
        if visibilityAnimation.fraction == 1 && !visibilityAnimation.isAnimating {
            hide()
            return
        }
        pointerMoved()
        let magnificationNeedsFrames = !holdsMagnification && (magnificationAnimation.isAnimating
            || magnificationFrameState.hasPendingTarget || magnificationFrameState.isTrackingInput(at: link.targetTimestamp))
        if !magnificationNeedsFrames && !visibilityAnimation.isAnimating && launchAnimations.isEmpty {
            link.isPaused = true
            magnificationFrameState.resetClock()
        }
    }

    private func updateMousePassthrough(at location: NSPoint) {
        guard let panel, !isMenuTracking, !isItemDragging else { return }
        let ignoresMouseEvents = !hasWindowEventRegion && !contentFrame.contains(location)
        if panel.ignoresMouseEvents != ignoresMouseEvents {
            panel.ignoresMouseEvents = ignoresMouseEvents
        }
    }

    private func applyGeometry(_ metrics: DockLayoutMetrics) {
        guard let panel else { return }
        let translation = visibilityAnimation.offset(distance: visibilityTravel, position: dockPosition)
        let windowFrame = canvasFrame.offsetBy(dx: translation.width, dy: translation.height)
        if !Self.framesApproximatelyEqual(panel.frame, windowFrame) {
            panel.setFrame(windowFrame, display: true, animate: false)
        }
        contentFrame = DockPanelGeometry.contentFrame(baseFrame: baseFrame, metrics: metrics,
                                                      position: dockPosition, limits: screenLimits)
            .offsetBy(dx: translation.width, dy: translation.height)
        residenceFrame = DockPanelHitGeometry.residenceFrame(for: contentFrame, position: dockPosition,
                                                              thickness: metrics.residenceThickness * metrics.scale)
        let layout = DockPresentationLayout(
            metrics: metrics,
            origin: CGPoint(x: contentFrame.minX - panel.frame.minX, y: panel.frame.maxY - contentFrame.maxY),
            canvasSize: panel.frame.size,
            launchProgress: launchAnimations.mapValues(\.value)
        )
        if presentation.layout != layout { presentation.layout = layout }
        hasWindowEventRegion = windowEventRegion?.update(window: panel, contentFrame: contentFrame) == true
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
            self.animateVisibility(hidden: true)
        }
    }

    private var visibilityTravel: Double {
        (dockPosition.isVertical ? baseFrame.width : baseFrame.height) + ScreenPlacementService.dockScreenMargin
    }

    private func animateVisibility(hidden: Bool) {
        guard let panel else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if hidden { hide() }
            else {
                visibilityAnimation = DockAutoHideAnimation()
                applyGeometry(presentation.metrics)
                panel.orderFrontRegardless()
            }
            return
        }
        let restThickness = dockPosition.isVertical ? baseFrame.width : baseFrame.height
        let currentGrowth = (layoutSettings.magnificationSize - layoutSettings.iconSize)
            * magnificationAnimation.value * presentation.metrics.scale
        let visibleExtent = restThickness + currentGrowth - visibilityTravel * visibilityAnimation.fraction
        let desiredExtent = hidden ? 0 : layoutSettings.iconSize * presentation.metrics.scale
        visibilityAnimation.setHidden(hidden, distance: desiredExtent - visibleExtent)
        if visibilityAnimation.isAnimating && displayLink?.isPaused == true {
            magnificationFrameState.resetClock()
            displayLink?.isPaused = false
        }
    }

    func cancelScheduledAutoHide() {
        if visibilityAnimation.target == 1 && panel?.isVisible == true { animateVisibility(hidden: false) }
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
        return residenceFrame.contains(location)
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
        let hostingView = DockHostingView(rootView: DockView(presentation: presentation).environmentObject(model), model: model)
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.acceptsMouseMovedEvents = true
        let link = panel.displayLink(target: self, selector: #selector(stepMagnification(_:)))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown, .scrollWheel]
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
        let growth = DockMagnificationLens.maximumExpansion(for: extra)
        let inwardExpansion = extra + DockLaunchAnimation.height(iconSize: settings.iconSize + extra / resting.scale) * resting.scale
        var frame = baseFrame
        if settings.dockPosition.isVertical {
            frame = frame.insetBy(dx: 0, dy: -growth)
            frame.size.width += inwardExpansion
            if settings.dockPosition == .right { frame.origin.x -= inwardExpansion }
        } else {
            frame = frame.insetBy(dx: -growth, dy: 0)
            frame.size.height += inwardExpansion
        }
        return frame.intersection(limits)
    }
}

enum DockPanelHitGeometry {
    static func contains(_ location: NSPoint, panelFrame: NSRect, position: DockPosition) -> Bool {
        residenceFrame(for: panelFrame, position: position).contains(location)
    }

    static func residenceFrame(for panelFrame: NSRect, position: DockPosition, thickness: Double? = nil) -> NSRect {
        var frame = panelFrame
        if let thickness {
            switch position {
            case .bottomCenter, .bottomLeft, .bottomRight: frame.size.height = thickness
            case .left: frame.size.width = thickness
            case .right:
                frame.origin.x = panelFrame.maxX - thickness
                frame.size.width = thickness
            }
        }
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
