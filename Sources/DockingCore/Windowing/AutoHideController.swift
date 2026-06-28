import AppKit
import Foundation

@MainActor
final class AutoHideController {
    private var edgePanels: [String: NSPanel] = [:]
    private var onEnter: ((NSScreen?) -> Void)?

    func update(settings: DockingSettings, dockFrame: NSRect, screen: NSScreen?, onEnter: @escaping (NSScreen?) -> Void) {
        self.onEnter = onEnter

        guard settings.dockVisibility == .autoHide else {
            close()
            return
        }

        let screens = Self.triggerScreens(for: settings, selectedScreen: screen, availableScreens: NSScreen.screens)
        let wantedKeys = Set(screens.map(screenKey))
        for (key, panel) in edgePanels where !wantedKeys.contains(key) {
            panel.close()
            edgePanels[key] = nil
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
            panel.collectionBehavior = collectionBehavior(for: settings)
            panel.orderFrontRegardless()
            edgePanels[key] = panel
        }
    }

    func close() {
        for panel in edgePanels.values {
            panel.close()
        }
        edgePanels = [:]
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

    private func screenKey(_ screen: NSScreen?) -> String {
        guard let screen else {
            return "fallback"
        }
        let frame = screen.frame
        return "\(screen.localizedName)-\(Int(frame.minX))-\(Int(frame.minY))-\(Int(frame.width))-\(Int(frame.height))"
    }

    private func collectionBehavior(for settings: DockingSettings) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.transient, .ignoresCycle]
        if settings.showOnAllSpaces {
            behavior.insert(.canJoinAllSpaces)
        }
        if settings.showOnFullScreenSpaces {
            behavior.insert(.fullScreenAuxiliary)
        }
        return behavior
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
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter()
    }
}
