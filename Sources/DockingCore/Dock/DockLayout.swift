import CoreGraphics
import Foundation

enum DockLayout {
    static func panelSize(itemCount: Int, widgetCount: Int, settings: DockingSettings) -> CGSize {
        let actionButtonCount = 1
        let iconWidth = settings.iconSize
        let widgetWidth = settings.widgetSize
        let itemTotal = Double(itemCount + actionButtonCount) * iconWidth
        let widgetTotal = Double(widgetCount) * widgetWidth
        let dividerWidth = widgetCount > 0 && itemCount > 0 ? 10.0 : 0.0
        let visibleCount = itemCount + widgetCount + actionButtonCount
        let spacingTotal = max(0, Double(visibleCount - 1)) * settings.spacing
        let paddingTotal = settings.dockSize * 0.32
        let longAxis = itemTotal + widgetTotal + dividerWidth + spacingTotal + paddingTotal

        // Left/right docks need a vertical long axis. We keep the short axis at
        // dockSize so the same sizing preference controls the visual thickness
        // regardless of edge, instead of introducing a second setting that would
        // make early-version behavior harder to reason about.
        if settings.dockPosition.isVertical {
            return CGSize(width: settings.dockSize, height: longAxis)
        }

        return CGSize(width: longAxis, height: settings.dockSize)
    }
}
