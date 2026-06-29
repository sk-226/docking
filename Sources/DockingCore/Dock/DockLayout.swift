import CoreGraphics
import Foundation

enum DockLayout {
    private static let dividerThickness = 1.0

    static func panelSize(
        itemCount: Int,
        settings: DockingSettings,
        hasSeparatedRunningItems: Bool = false
    ) -> CGSize {
        let actionButtonCount = 1
        let iconWidth = settings.iconSize
        let widgetWidths = settings.enabledWidgetWidths
        let itemTotal = Double(itemCount + actionButtonCount) * iconWidth
        let widgetTotal = widgetWidths.reduce(0, +)
        let dividerCount = dividerCount(
            itemCount: itemCount,
            widgetCount: widgetWidths.count,
            hasSeparatedRunningItems: hasSeparatedRunningItems
        )
        let dividerTotal = Double(dividerCount) * dividerThickness
        let visibleCount = itemCount + widgetWidths.count + actionButtonCount + dividerCount
        let spacingTotal = max(0, Double(visibleCount - 1)) * settings.spacing
        let shortAxis = shortAxisSize(settings: settings)
        let paddingTotal = shortAxis * 0.32
        let longAxis = itemTotal + widgetTotal + dividerTotal + spacingTotal + paddingTotal

        if settings.dockPosition.isVertical {
            return CGSize(width: shortAxis, height: longAxis)
        }

        return CGSize(width: longAxis, height: shortAxis)
    }

    static func shortAxisSize(settings: DockingSettings) -> Double {
        guard settings.dockPosition.isVertical else {
            return settings.effectiveDockThickness
        }

        // Side docks still render the same widget controls as bottom docks.
        // Clamping the panel to only `dockSize` made detailed widgets overflow
        // the glass, while inventing a second vertical-only widget model would
        // add settings and state for a 0.0.0 app before the product has proven
        // it needs that complexity. The invariant here is simple: the resident
        // panel must be at least as wide as the widest enabled child it renders.
        return max(settings.effectiveDockThickness, settings.enabledWidgetWidths.max() ?? 0)
    }

    static func dividerCount(
        itemCount: Int,
        widgetCount: Int,
        hasSeparatedRunningItems: Bool
    ) -> Int {
        var count = 0
        if hasSeparatedRunningItems {
            // DockView intentionally separates transient running apps even when
            // widgets are disabled. Counting this divider here keeps the
            // AppKit panel frame honest instead of relying on SwiftUI overflow.
            count += 1
        }
        if widgetCount > 0 && itemCount > 0 {
            // Widgets are a different class of dock item, so they get their own
            // separator after apps. This condition mirrors DockView exactly:
            // no app items means there is nothing meaningful to separate.
            count += 1
        }
        return count
    }
}
