import Foundation

struct DockLayoutMetrics: Equatable {
    var iconSizes: [Double]
    var iconCenters: [Double]
    var iconLeadingInsets: [Double]
    var panelSize: CGSize
    var surfaceSize: CGSize
    var scale: Double
    var originShift: Double
    var padding: Double
    var residenceThickness: Double = 0

    var scaledPanelSize: CGSize {
        CGSize(width: panelSize.width * scale, height: panelSize.height * scale)
    }
}

// Room before/after the resting dock along its item order, in unscaled points.
// For vertical docks "leading" means above, not below. Include the window's
// screen clamp in the layout calculation so it cannot displace the hover peak.
struct DockMagnificationBounds {
    var leading: Double = .infinity
    var trailing: Double = .infinity

    func originShift(for growth: Double, preferred: Double) -> Double {
        min(max(preferred, growth - max(0, trailing)), max(0, leading))
    }
}

enum DockLayout {
    static let addButtonSize = 20.0
    static let indicatorSpace = 6.0
    static let edgeInset = 6.0

    static func panelSize(itemCount: Int, settings: DockingSettings, hasDocuments: Bool = false) -> CGSize {
        metrics(itemCount: itemCount, settings: settings, documentStart: hasDocuments ? itemCount : nil).panelSize
    }

    static func shortAxisSize(settings: DockingSettings) -> Double {
        settings.effectiveDockThickness
    }

    static func metrics(
        itemCount: Int,
        settings: DockingSettings,
        documentStart: Int? = nil,
        runningSectionStart: Int? = nil,
        maximumLength: Double = .infinity,
        pointerOffset: Double? = nil,
        magnificationProgress: Double = 1,
        magnificationBounds: DockMagnificationBounds = DockMagnificationBounds()
    ) -> DockLayoutMetrics {
        let baseSize = settings.iconSize
        let padding = max(6, baseSize * 0.16)
        let vertical = settings.dockPosition.isVertical
        let widgets = settings.enabledWidgetWidths
        let sectionStarts = Set([documentStart, runningSectionStart].compactMap { $0 })
        let dividers = sectionStarts.count + (widgets.isEmpty || itemCount == 0 ? 0 : 1)
        let spacing = settings.spacing
        let widgetLength = vertical ? Double(widgets.count) * settings.widgetTileHeight : widgets.reduce(0, +)
        let gapCount = itemCount + widgets.count + dividers
        let baseLength = Double(itemCount) * baseSize + widgetLength + addButtonSize + Double(dividers) + Double(gapCount) * spacing + padding * 2
        let maximumGrowth = max(0, settings.magnificationSize - baseSize)
        let reservedGrowth = settings.magnificationEnabled && itemCount > 0
            ? DockMagnificationLens.maximumExpansion(for: maximumGrowth) : 0
        let scale = min(1, maximumLength / (baseLength + reservedGrowth))
        var centers: [Double] = []
        var cursor = padding
        for index in 0..<itemCount {
            if sectionStarts.contains(index) { cursor += 1 + spacing }
            centers.append(cursor + baseSize / 2)
            cursor += baseSize + spacing
        }

        let availableGrowth = max(0, min(maximumLength / scale - baseLength,
                                        max(0, magnificationBounds.leading) + max(0, magnificationBounds.trailing)))
        let lens = DockMagnificationLens(centers: centers, baseSize: baseSize,
                                         maximumGrowth: maximumGrowth,
                                         availableGrowth: availableGrowth, bounds: magnificationBounds,
                                         progress: magnificationProgress, focusBounds: padding...(baseLength - padding))
        let geometry: DockMagnificationLens.Geometry
        if settings.magnificationEnabled, let pointerOffset, pointerOffset.isFinite,
           !centers.isEmpty, availableGrowth > 0, lens.maximumGrowth > 0, magnificationProgress > 0 {
            geometry = lens.geometry(at: lens.focus(for: pointerOffset))
        } else {
            geometry = .init(sizes: Array(repeating: baseSize, count: itemCount),
                             leadingInsets: Array(repeating: 0, count: itemCount), growth: 0, originShift: 0, currentGrowth: 0)
        }
        let sizes = geometry.sizes
        let growth = geometry.growth
        let length = baseLength + growth
        let thickness = settings.effectiveDockThickness
        let expandedThickness = max(thickness, (sizes.max() ?? baseSize) + edgeInset * 2)
        return DockLayoutMetrics(
            iconSizes: sizes,
            iconCenters: centers,
            iconLeadingInsets: geometry.leadingInsets,
            panelSize: CGSize(width: vertical ? expandedThickness : length, height: vertical ? length : expandedThickness),
            surfaceSize: CGSize(width: vertical ? thickness : length, height: vertical ? length : thickness),
            scale: scale,
            originShift: geometry.originShift,
            padding: padding,
            residenceThickness: max(thickness, baseSize + edgeInset + geometry.currentGrowth) + 10
        )
    }
}

struct DockMagnificationLens {
    struct Geometry {
        let sizes: [Double]
        let leadingInsets: [Double]
        let growth: Double
        let originShift: Double
        let currentGrowth: Double
    }

    // Dock-2427.6 の定数ビット列．出典と精度の範囲は NATIVE_MAGNIFICATION.md を参照．
    static let nativePi = Double(Float(bitPattern: 0x40490fdb))

    let centers: [Double]
    let baseSize: Double
    let maximumGrowth: Double
    let availableGrowth: Double
    let bounds: DockMagnificationBounds
    var progress: Double = 1
    var focusBounds: ClosedRange<Double>?

    var radius: Double { baseSize * 3 }

    static func maximumExpansion(for growth: Double) -> Double {
        growth / sin(nativePi / 12)
    }

    func geometry(at focus: Double) -> Geometry {
        guard let first = centers.first, let last = centers.last else {
            return Geometry(sizes: [], leadingInsets: [], growth: 0, originShift: 0, currentGrowth: 0)
        }
        let amplitude = Self.maximumExpansion(for: maximumGrowth) / 2
        func displacement(_ coordinate: Double) -> Double {
            let distance = coordinate - focus
            if distance <= -radius { return -amplitude }
            if distance >= radius { return amplitude }
            return amplitude * sin(Self.nativePi * distance / (2 * radius))
        }
        let fullGrowth = displacement(last + baseSize / 2) - displacement(first - baseSize / 2)
        let fraction = min(1, max(0, progress)) * (fullGrowth > 0 ? min(1, availableGrowth / fullGrowth) : 0)
        var sizes: [Double] = []
        var insets: [Double] = []
        var previousEnd = displacement(first - baseSize / 2)
        for center in centers {
            let start = displacement(center - baseSize / 2)
            let end = displacement(center + baseSize / 2)
            sizes.append(baseSize + (end - start) * fraction)
            insets.append((start - previousEnd) * fraction)
            previousEnd = end
        }
        let growth = fullGrowth * fraction
        let originShift = bounds.originShift(for: growth, preferred: -displacement(first - baseSize / 2) * fraction)
        return Geometry(sizes: sizes, leadingInsets: insets, growth: growth, originShift: originShift,
                        currentGrowth: maximumGrowth * fraction)
    }

    func focus(for pointer: Double) -> Double {
        guard let first = centers.first, let last = centers.last else { return pointer }
        let range = focusBounds ?? (first - baseSize / 2)...(last + baseSize / 2)
        return min(max(pointer, range.lowerBound), range.upperBound)
    }
}
