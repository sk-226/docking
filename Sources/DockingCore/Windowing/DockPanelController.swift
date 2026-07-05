import AppKit
import SwiftUI

@MainActor
final class DockPanelController {
    private var panel: NSPanel?
    private let autoHideController = AutoHideController()
    private var revealScreen: NSScreen?
    private var autoHideGeneration = 0
    private var isAutoHideScheduled = false

    var frame: NSRect? {
        panel?.frame
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
    }

    func hide() {
        cancelScheduledAutoHide()
        panel?.orderOut(nil)
    }

    func orderFront() {
        cancelScheduledAutoHide()
        panel?.orderFrontRegardless()
    }

    func close() {
        cancelScheduledAutoHide()
        autoHideController.close()
        panel?.close()
        panel = nil
    }

    func applySettings(model: DockingAppModel) {
        guard let panel else {
            return
        }

        let settings = model.settings
        if let revealScreen,
           !NSScreen.screens.contains(where: { ScreenPlacementService.sameDisplay($0, revealScreen) }) {
            self.revealScreen = nil
        }

        if settings.dockVisibility != .autoHide || !settings.dockPosition.isBottom {
            revealScreen = nil
        }

        let screen = revealScreen ?? ScreenPlacementService.dockScreen(for: settings)
        let size = DockLayout.panelSize(
            itemCount: model.visibleAppItemCount,
            settings: settings,
            hasSeparatedRunningItems: model.hasSeparatedRunningItems
        )
        let frame = ScreenPlacementService.dockFrame(size: size, on: screen, position: settings.dockPosition)
        // Avoid AppKit's window-frame animation here. The dock frame is often
        // applied while SwiftUI is still laying out the hosting view during
        // launch, Space changes, or live settings updates; asking AppKit to
        // animate the same transaction can trigger layout recursion warnings.
        // Docking's visible motion comes from lightweight SwiftUI hover/detail
        // transitions, not from resizing the resident panel itself.
        panel.setFrame(frame, display: true, animate: false)
        panel.alphaValue = settings.opacity
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
            dockFrame: frame,
            screen: screen,
            onEnter: { [weak self, weak model] screen in
                guard let model else {
                    return
                }
                self?.reveal(
                    on: screen,
                    settings: model.settings,
                    itemCount: model.visibleAppItemCount,
                    hasSeparatedRunningItems: model.hasSeparatedRunningItems
                )
            },
            onTriggerContact: { [weak self] _ in
                guard self?.isVisible == true else {
                    return
                }
                self?.cancelScheduledAutoHide()
            },
            onPointerOutsideTrigger: { [weak model] location in
                model?.scheduleAutoHideIfNeeded(pointerLocation: location)
            }
        )
    }

    private func reveal(on screen: NSScreen?, settings: DockingSettings, itemCount: Int, hasSeparatedRunningItems: Bool) {
        guard let panel else {
            return
        }

        revealScreen = screen
        let size = DockLayout.panelSize(
            itemCount: itemCount,
            settings: settings,
            hasSeparatedRunningItems: hasSeparatedRunningItems
        )
        let frame = ScreenPlacementService.dockFrame(size: size, on: screen ?? ScreenPlacementService.dockScreen(for: settings), position: settings.dockPosition)
        cancelScheduledAutoHide()
        guard !panel.isVisible || !Self.framesApproximatelyEqual(panel.frame, frame) else {
            return
        }
        panel.setFrame(frame, display: true, animate: false)
        panel.orderFrontRegardless()
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
        panel?.isVisible == true && panel?.frame.contains(location) == true
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
        panel.contentView = NSHostingView(rootView: DockView().environmentObject(model))
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
