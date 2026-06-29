import AppKit
import SwiftUI

@MainActor
final class FolderStackPanelController {
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var visibleItemID: UUID?
    private var onClose: (() -> Void)?
    private static let animationDuration: TimeInterval = 0.12

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle(item: DockItem, model: DockingAppModel, dockFrame: NSRect?, anchorFrame: NSRect?, onClose: @escaping () -> Void) {
        guard item.isFolder else {
            return
        }

        if visibleItemID == item.id {
            close()
            return
        }

        show(item: item, model: model, dockFrame: dockFrame, anchorFrame: anchorFrame, onClose: onClose)
    }

    func show(item: DockItem, model: DockingAppModel, dockFrame: NSRect?, anchorFrame: NSRect?, onClose: @escaping () -> Void) {
        close(animated: false, notifyClose: false)
        visibleItemID = item.id
        self.onClose = onClose

        let entries = FolderStackService.entries(for: item)
        let size = FolderStackPresentation.panelSize(for: item, entryCount: entries.count)
        let panel = makePanel(item: item, entries: entries, model: model)
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
        close(animated: true, notifyClose: true)
    }

    private func close(animated: Bool, notifyClose: Bool) {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
        visibleItemID = nil

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

        // This mirrors widget panel behavior: a brief fade makes the floating
        // panel feel intentionally attached to the dock icon, while Reduced
        // Motion remains a hard opt-out for animation.
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

    private func makePanel(item: DockItem, entries: [FolderStackEntry], model: DockingAppModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = item.title
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: FolderStackPanelView(item: item, entries: entries)
                .environmentObject(model)
        )
        return panel
    }

    private func installDismissMonitors(panel: NSPanel, anchorFrame: NSRect?) {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            if event.type == .keyDown, event.keyCode == 53 {
                self?.close(animated: true, notifyClose: true)
                return nil
            }

            if let panel,
               Self.shouldDismissPointerEvent(
                   pointerLocation: NSEvent.mouseLocation,
                   panelFrame: panel.frame,
                   anchorFrame: anchorFrame
               ) {
                self?.close(animated: true, notifyClose: true)
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
                self?.close(animated: true, notifyClose: true)
            }
        }
    }

    nonisolated static func shouldDismissPointerEvent(pointerLocation: NSPoint, panelFrame: NSRect, anchorFrame: NSRect?) -> Bool {
        if panelFrame.contains(pointerLocation) {
            return false
        }

        // The source folder icon owns the toggle action. If event monitoring
        // closed the panel before SwiftUI received that click, the same click
        // could close and immediately reopen the stack. Exempting the anchor
        // keeps "click the folder again to close" deterministic.
        if let anchorFrame, anchorFrame.insetBy(dx: -6, dy: -6).contains(pointerLocation) {
            return false
        }

        return true
    }
}
