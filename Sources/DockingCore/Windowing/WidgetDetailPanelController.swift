import AppKit
import SwiftUI

@MainActor
final class WidgetDetailPanelController {
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var visibleKind: DockWidgetKind?
    private var recentlyDismissedKind: DockWidgetKind?
    private var recentlyDismissedAt: TimeInterval = 0
    private var onClose: (() -> Void)?
    private static let animationDuration: TimeInterval = 0.12
    private nonisolated static let retoggleSuppressionInterval: TimeInterval = 0.35

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle(kind: DockWidgetKind, model: DockingAppModel, dockFrame: NSRect?, anchorFrame: NSRect?, onClose: @escaping () -> Void) {
        if visibleKind == kind {
            close()
            return
        }
        if Self.shouldSuppressImmediateRetoggle(
            recentlyDismissedKind: recentlyDismissedKind,
            dismissedAt: recentlyDismissedAt,
            requestedKind: kind,
            now: ProcessInfo.processInfo.systemUptime
        ) {
            recentlyDismissedKind = nil
            return
        }
        show(kind: kind, model: model, dockFrame: dockFrame, anchorFrame: anchorFrame, onClose: onClose)
    }

    func show(kind: DockWidgetKind, model: DockingAppModel, dockFrame: NSRect?, anchorFrame: NSRect?, onClose: @escaping () -> Void) {
        // Switching directly from one widget to another should feel immediate.
        // We skip the close animation in this path so the old panel cannot fade
        // over the newly selected panel for a few frames.
        close(animated: false, rememberForRetoggleSuppression: false, notifyClose: false)
        visibleKind = kind
        recentlyDismissedKind = nil
        self.onClose = onClose

        let size = CGSize(width: 380, height: kind == .calendar ? 430 : 380)
        let panel = makePanel(kind: kind, model: model)
        let frame = ScreenPlacementService.detailFrame(
            size: size,
            dockFrame: dockFrame ?? ScreenPlacementService.dockFrame(size: CGSize(width: 420, height: 72), position: model.settings.dockPosition),
            anchorFrame: anchorFrame,
            position: model.settings.dockPosition
        )
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        installDismissMonitors(panel: panel, anchorFrame: anchorFrame)
        showPanel(panel, targetAlpha: model.settings.opacity)
    }

    func close() {
        close(animated: true, rememberForRetoggleSuppression: false, notifyClose: true)
    }

    private func close(animated: Bool, rememberForRetoggleSuppression: Bool, notifyClose: Bool) {
        if rememberForRetoggleSuppression, let visibleKind {
            recentlyDismissedKind = visibleKind
            recentlyDismissedAt = ProcessInfo.processInfo.systemUptime
        } else if !rememberForRetoggleSuppression {
            recentlyDismissedKind = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
        visibleKind = nil
        let panelToClose = panel
        panel = nil
        let closeHandler = notifyClose ? onClose : nil
        if notifyClose {
            onClose = nil
        }

        guard let panelToClose else {
            closeHandler?()
            return
        }

        // A short fade gives the floating widget panel a deliberate open/close
        // affordance without introducing a persistent animation loop. Reduced
        // Motion is treated as a hard user preference, so those users get the
        // same state change without animation.
        guard animated,
              panelToClose.isVisible,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panelToClose.close()
            closeHandler?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panelToClose.animator().alphaValue = 0
        } completionHandler: {
            panelToClose.close()
            closeHandler?()
        }
    }

    private func showPanel(_ panel: NSPanel, targetAlpha: Double) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = targetAlpha
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = targetAlpha
        }
    }

    func close(kind: DockWidgetKind) {
        guard visibleKind == kind else {
            return
        }
        close()
    }

    private func makePanel(kind: DockWidgetKind, model: DockingAppModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = kind == .calendar ? "Calendar" : "Weather"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: WidgetDetailPanelRoot(kind: kind)
                .environmentObject(model)
        )
        return panel
    }

    private func installDismissMonitors(panel: NSPanel, anchorFrame: NSRect?) {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            if event.type == .keyDown, event.keyCode == 53 {
                self?.close(animated: true, rememberForRetoggleSuppression: false, notifyClose: true)
                return nil
            }

            if let panel,
               Self.shouldDismissPointerEvent(
                   pointerLocation: NSEvent.mouseLocation,
                   panelFrame: panel.frame,
                   anchorFrame: anchorFrame
               ) {
                self?.close(animated: true, rememberForRetoggleSuppression: true, notifyClose: true)
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] _ in
            if let panel,
               Self.shouldDismissPointerEvent(
                   pointerLocation: NSEvent.mouseLocation,
                   panelFrame: panel.frame,
                   anchorFrame: anchorFrame
               ) {
                self?.close(animated: true, rememberForRetoggleSuppression: true, notifyClose: true)
            }
        }
    }

    nonisolated static func shouldSuppressImmediateRetoggle(
        recentlyDismissedKind: DockWidgetKind?,
        dismissedAt: TimeInterval,
        requestedKind: DockWidgetKind,
        now: TimeInterval
    ) -> Bool {
        // Event monitors see the pointer event before SwiftUI buttons do. If
        // that pointer event dismisses a visible widget panel, the button action
        // for the same widget can arrive a few milliseconds later and would
        // otherwise reopen the panel. The short uptime-based window is not user
        // visible; it only connects the two callbacks that belong to the same
        // physical click. Uptime avoids wall-clock changes affecting UI logic.
        recentlyDismissedKind == requestedKind && now - dismissedAt <= retoggleSuppressionInterval
    }

    nonisolated static func shouldDismissPointerEvent(pointerLocation: NSPoint, panelFrame: NSRect, anchorFrame: NSRect?) -> Bool {
        if panelFrame.contains(pointerLocation) {
            return false
        }

        // NSEvent monitors run before SwiftUI button actions. If the user
        // clicks the same widget that opened the panel, treating that click as
        // a normal outside click closes the panel first; the widget's own
        // action then runs and reopens it. Exempting the current anchor leaves
        // the source of truth in `toggle(kind:)`: same widget closes, different
        // widgets still switch panels, and ordinary outside clicks still
        // dismiss. A small tolerance absorbs sub-pixel frame conversion and
        // icon hover scaling without making the whole dock a non-dismiss zone.
        if let anchorFrame, anchorFrame.insetBy(dx: -6, dy: -6).contains(pointerLocation) {
            return false
        }

        return true
    }
}
