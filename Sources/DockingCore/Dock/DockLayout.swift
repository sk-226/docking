import CoreGraphics
import Foundation

struct DockLayoutMetrics: Equatable {
    var iconSizes: [Double]
    var iconCenters: [Double]
    var panelSize: CGSize
    var surfaceSize: CGSize
    var scale: Double
    var originShift: Double
    var padding: Double

    var scaledPanelSize: CGSize {
        CGSize(width: panelSize.width * scale, height: panelSize.height * scale)
    }

    func approaching(_ target: DockLayoutMetrics, elapsed: TimeInterval) -> DockLayoutMetrics {
        guard iconSizes.count == target.iconSizes.count else { return target }
        let distance = max(zip(iconSizes, target.iconSizes).map { abs($0 - $1) }.max() ?? 0,
                           abs(originShift - target.originShift))
        guard distance > 0.01 else { return target }
        let progress = 1 - exp(-max(0, elapsed) / 0.035)
        func blend(_ current: Double, _ next: Double) -> Double {
            current + (next - current) * progress
        }
        var result = target
        result.iconSizes = zip(iconSizes, target.iconSizes).map(blend)
        result.originShift = blend(originShift, target.originShift)
        result.panelSize = CGSize(width: blend(panelSize.width, target.panelSize.width),
                                  height: blend(panelSize.height, target.panelSize.height))
        result.surfaceSize = CGSize(width: blend(surfaceSize.width, target.surfaceSize.width),
                                    height: blend(surfaceSize.height, target.surfaceSize.height))
        return result
    }
}

enum DockLayout {
    static let addButtonSize = 20.0
    static let indicatorSpace = 6.0
    static let edgeInset = 6.0

    static func panelSize(itemCount: Int, settings: DockingSettings, hasSeparatedRunningItems: Bool = false) -> CGSize {
        metrics(itemCount: itemCount, settings: settings, separatedRunningStart: hasSeparatedRunningItems ? itemCount : nil).panelSize
    }

    static func shortAxisSize(settings: DockingSettings) -> Double {
        settings.effectiveDockThickness
    }

    static func dividerCount(itemCount: Int, widgetCount: Int, hasSeparatedRunningItems: Bool) -> Int {
        (hasSeparatedRunningItems ? 1 : 0) + (widgetCount > 0 && itemCount > 0 ? 1 : 0)
    }

    static func metrics(
        itemCount: Int,
        settings: DockingSettings,
        separatedRunningStart: Int? = nil,
        maximumLength: Double = .infinity,
        pointerOffset: Double? = nil
    ) -> DockLayoutMetrics {
        let baseSize = settings.iconSize
        let padding = max(6, baseSize * 0.16)
        let vertical = settings.dockPosition.isVertical
        let widgets = settings.enabledWidgetWidths
        let dividers = dividerCount(itemCount: itemCount, widgetCount: widgets.count, hasSeparatedRunningItems: separatedRunningStart != nil)
        let spacing = settings.spacing
        let widgetLength = vertical ? Double(widgets.count) * settings.widgetTileHeight : widgets.reduce(0, +)
        let gapCount = itemCount + widgets.count + dividers
        let baseLength = Double(itemCount) * baseSize + widgetLength + addButtonSize + Double(dividers) + Double(gapCount) * spacing + padding * 2
        let scale = min(1, maximumLength / baseLength)
        var centers: [Double] = []
        var cursor = padding
        for index in 0..<itemCount {
            if index == separatedRunningStart { cursor += 1 + spacing }
            centers.append(cursor + baseSize / 2)
            cursor += baseSize + spacing
        }

        var sizes = centers.map { center in
            guard settings.magnificationEnabled, let pointerOffset else { return baseSize }
            let distance = abs(center - pointerOffset) / ((baseSize + spacing) * 2)
            guard distance < 1 else { return baseSize }
            let weight = (cos(distance * .pi) + 1) / 2
            return baseSize + max(0, settings.magnificationSize - baseSize) * weight
        }
        let requestedGrowth = sizes.reduce(0) { $0 + $1 - baseSize }
        let availableGrowth = max(0, maximumLength / scale - baseLength)
        if requestedGrowth > availableGrowth {
            sizes = sizes.map { baseSize + ($0 - baseSize) * availableGrowth / requestedGrowth }
        }
        let growth = sizes.reduce(0) { $0 + $1 - baseSize }
        var originShift = growth / 2
        if let pointerOffset {
            originShift = zip(centers, sizes).reduce(0) { result, item in
                let fraction = min(1, max(0, (pointerOffset - (item.0 - baseSize / 2)) / baseSize))
                return result + (item.1 - baseSize) * fraction
            }
        }
        let length = baseLength + growth
        let thickness = settings.effectiveDockThickness
        let expandedThickness = max(thickness, (sizes.max() ?? baseSize) + edgeInset * 2)
        return DockLayoutMetrics(
            iconSizes: sizes,
            iconCenters: centers,
            panelSize: CGSize(width: vertical ? expandedThickness : length, height: vertical ? length : expandedThickness),
            surfaceSize: CGSize(width: vertical ? thickness : length, height: vertical ? length : thickness),
            scale: scale,
            originShift: originShift,
            padding: padding
        )
    }
}
