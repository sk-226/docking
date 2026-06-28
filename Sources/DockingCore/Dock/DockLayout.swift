import CoreGraphics
import Foundation

enum DockLayout {
    static func panelSize(itemCount: Int, settings: DockingSettings) -> CGSize {
        let actionButtonCount = 1
        let iconWidth = settings.iconSize
        let widgetWidths = settings.enabledWidgetWidths
        let itemTotal = Double(itemCount + actionButtonCount) * iconWidth
        let widgetTotal = widgetWidths.reduce(0, +)
        let dividerWidth = widgetWidths.isEmpty || itemCount == 0 ? 0.0 : 10.0
        let visibleCount = itemCount + widgetWidths.count + actionButtonCount
        let spacingTotal = max(0, Double(visibleCount - 1)) * settings.spacing
        let shortAxis = settings.effectiveDockThickness
        let paddingTotal = shortAxis * 0.32
        let longAxis = itemTotal + widgetTotal + dividerWidth + spacingTotal + paddingTotal

        // Left/right docks need a vertical long axis. We keep the short axis at
        // the effective dock thickness so a large widget preset cannot overflow
        // the glass surface. A separate vertical-only size would make this
        // early 0.0.0 settings model harder to understand without buying a real
        // product capability.
        if settings.dockPosition.isVertical {
            return CGSize(width: shortAxis, height: longAxis)
        }

        return CGSize(width: longAxis, height: shortAxis)
    }
}
