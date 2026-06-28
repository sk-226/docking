import AppKit
import Foundation

enum ScreenPlacementService {
    static func dockScreen(for settings: DockingSettings) -> NSScreen? {
        switch settings.displayMode {
        case .main:
            return NSScreen.main ?? NSScreen.screens.first
        case .pointer:
            return screenContainingPoint(NSEvent.mouseLocation) ?? NSScreen.main ?? NSScreen.screens.first
        case .specific:
            if let dockDisplayID = settings.dockDisplayID,
               let screen = NSScreen.screens.first(where: { displayID(for: $0) == dockDisplayID }) {
                return screen
            }
            return NSScreen.main ?? NSScreen.screens.first
        }
    }

    static func availableDisplays() -> [DisplaySummary] {
        NSScreen.screens.compactMap { screen in
            guard let id = displayID(for: screen) else {
                return nil
            }

            let frame = screen.frame
            return DisplaySummary(
                id: id,
                name: screen.localizedName,
                frameDescription: "\(Int(frame.width))x\(Int(frame.height)) @ \(Int(frame.minX)),\(Int(frame.minY))"
            )
        }
    }

    static func dockFrame(size: CGSize, on screen: NSScreen? = NSScreen.main, position: DockPosition = .bottomCenter) -> NSRect {
        let visibleFrame = (screen ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let margin: CGFloat = 10
        let width = min(size.width, visibleFrame.width - margin * 2)
        let height = min(size.height, visibleFrame.height - margin * 2)

        let x: CGFloat
        let y: CGFloat
        switch position {
        case .bottomCenter:
            x = visibleFrame.midX - width / 2
            y = visibleFrame.minY + margin
        case .bottomLeft:
            x = visibleFrame.minX + margin
            y = visibleFrame.minY + margin
        case .bottomRight:
            x = visibleFrame.maxX - width - margin
            y = visibleFrame.minY + margin
        case .left:
            x = visibleFrame.minX + margin
            y = visibleFrame.midY - height / 2
        case .right:
            x = visibleFrame.maxX - width - margin
            y = visibleFrame.midY - height / 2
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func detailFrame(size: CGSize, dockFrame: NSRect, anchorFrame: NSRect? = nil, position: DockPosition = .bottomCenter, on screen: NSScreen? = nil) -> NSRect {
        let targetScreen = screen ?? screenContaining(anchorFrame ?? dockFrame) ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let margin: CGFloat = 12
        let anchor = anchorFrame ?? dockFrame

        let proposedX: CGFloat
        let proposedY: CGFloat
        switch position {
        case .left:
            proposedX = dockFrame.maxX + margin
            proposedY = anchor.midY - size.height / 2
        case .right:
            proposedX = dockFrame.minX - size.width - margin
            proposedY = anchor.midY - size.height / 2
        case .bottomCenter, .bottomLeft, .bottomRight:
            // Prefer the clicked widget's center when SwiftUI can report it.
            // The dock center remains a fallback for early startup or if AppKit
            // has not attached the hosted view to a window yet; silently
            // refusing to open a panel would be worse than a centered fallback.
            proposedX = anchor.midX - size.width / 2
            proposedY = max(anchor.maxY, dockFrame.maxY) + margin
        }

        let x = min(max(proposedX, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        let y = min(max(proposedY, visibleFrame.minY + margin), visibleFrame.maxY - size.height - margin)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    static func edgeTriggerFrame(dockFrame: NSRect, position: DockPosition = .bottomCenter, on screen: NSScreen? = NSScreen.main) -> NSRect {
        let screenFrame = (screen ?? NSScreen.screens.first)?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let thickness: CGFloat = 8

        switch position {
        case .bottomCenter, .bottomLeft, .bottomRight:
            let clampedWidth = min(dockFrame.width + 64, screenFrame.width)
            let x = min(max(dockFrame.midX - clampedWidth / 2, screenFrame.minX), screenFrame.maxX - clampedWidth)
            // Auto-hide needs to wake from the physical screen edge, not from
            // visibleFrame. visibleFrame excludes Apple's Dock when it is shown,
            // which made Docking impossible to reveal by pushing to the bottom
            // edge in exactly the configuration users expect a Dock to support.
            return NSRect(x: x, y: screenFrame.minY, width: clampedWidth, height: thickness)
        case .left:
            let clampedHeight = min(dockFrame.height + 64, screenFrame.height)
            let y = min(max(dockFrame.midY - clampedHeight / 2, screenFrame.minY), screenFrame.maxY - clampedHeight)
            return NSRect(x: screenFrame.minX, y: y, width: thickness, height: clampedHeight)
        case .right:
            let clampedHeight = min(dockFrame.height + 64, screenFrame.height)
            let y = min(max(dockFrame.midY - clampedHeight / 2, screenFrame.minY), screenFrame.maxY - clampedHeight)
            return NSRect(x: screenFrame.maxX - thickness, y: y, width: thickness, height: clampedHeight)
        }
    }

    private static func screenContaining(_ rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.intersects(rect) || screen.visibleFrame.intersects(rect)
        }
    }

    private static func screenContainingPoint(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.contains(point)
        }
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
