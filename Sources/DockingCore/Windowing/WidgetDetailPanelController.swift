import AppKit
import SwiftUI

@MainActor
final class WidgetDetailPanelController {
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var visibleKind: DockWidgetKind?
    private static let animationDuration: TimeInterval = 0.12

    func toggle(kind: DockWidgetKind, model: DockingAppModel, dockFrame: NSRect?, anchorFrame: NSRect?) {
        if visibleKind == kind {
            close()
            return
        }
        show(kind: kind, model: model, dockFrame: dockFrame, anchorFrame: anchorFrame)
    }

    func show(kind: DockWidgetKind, model: DockingAppModel, dockFrame: NSRect?, anchorFrame: NSRect?) {
        // Switching directly from one widget to another should feel immediate.
        // We skip the close animation in this path so the old panel cannot fade
        // over the newly selected panel for a few frames.
        close(animated: false)
        visibleKind = kind

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
        close(animated: true)
    }

    private func close(animated: Bool) {
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

        guard let panelToClose else {
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
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panelToClose.animator().alphaValue = 0
        } completionHandler: {
            panelToClose.close()
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
                self?.close()
                return nil
            }

            if let panel,
               Self.shouldDismissPointerEvent(
                   pointerLocation: NSEvent.mouseLocation,
                   panelFrame: panel.frame,
                   anchorFrame: anchorFrame
               ) {
                self?.close()
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
                self?.close()
            }
        }
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
