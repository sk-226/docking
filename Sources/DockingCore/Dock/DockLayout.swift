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

// Room before/after the resting dock along its item order, in unscaled points.
// For vertical docks "leading" means above, not below. Include the window's
// screen clamp in the layout calculation so it cannot displace the hover peak.
struct DockMagnificationBounds {
    var leading: Double = .infinity
    var trailing: Double = .infinity

    func originShift(for growth: Double) -> Double {
        min(max(growth / 2, growth - max(0, trailing)), max(0, leading))
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
        pointerOffset: Double? = nil,
        magnificationBounds: DockMagnificationBounds = DockMagnificationBounds()
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

        let availableGrowth = max(0, min(maximumLength / scale - baseLength,
                                        max(0, magnificationBounds.leading) + max(0, magnificationBounds.trailing)))
        let lens = DockMagnificationLens(centers: centers, baseSize: baseSize,
                                         radius: (baseSize + spacing) * 2,
                                         maximumGrowth: max(0, settings.magnificationSize - baseSize),
                                         availableGrowth: availableGrowth, bounds: magnificationBounds)
        let sizes: [Double]
        if settings.magnificationEnabled, let pointerOffset, pointerOffset.isFinite,
           !centers.isEmpty, availableGrowth > 0, lens.maximumGrowth > 0 {
            // pointerOffset is measured from the *resting frame on screen*, not
            // from animated content. Solve against target geometry only: feeding
            // presentation geometry back into this mapping creates hover jitter.
            sizes = lens.sizes(at: lens.focus(for: pointerOffset))
        } else {
            sizes = Array(repeating: baseSize, count: itemCount)
        }
        let growth = sizes.reduce(0) { $0 + $1 - baseSize }
        let length = baseLength + growth
        let thickness = settings.effectiveDockThickness
        let expandedThickness = max(thickness, (sizes.max() ?? baseSize) + edgeInset * 2)
        return DockLayoutMetrics(
            iconSizes: sizes,
            iconCenters: centers,
            panelSize: CGSize(width: vertical ? expandedThickness : length, height: vertical ? length : expandedThickness),
            surfaceSize: CGSize(width: vertical ? thickness : length, height: vertical ? length : thickness),
            scale: scale,
            originShift: magnificationBounds.originShift(for: growth),
            padding: padding
        )
    }
}

// A center-to-center mapping avoids the discontinuous slope of the old
// per-icon growth fractions (which can even reverse direction at high zoom).
// This is a geometric model, not a claim to reproduce Apple's private curve.
struct DockMagnificationLens {
    let centers: [Double]
    let baseSize: Double
    let radius: Double
    let maximumGrowth: Double
    let availableGrowth: Double
    let bounds: DockMagnificationBounds

    func sizes(at focus: Double) -> [Double] {
        var sizes = centers.map { center in
            let distance = abs(center - focus) / radius
            guard distance < 1 else { return baseSize }
            return baseSize + maximumGrowth * (cos(distance * .pi) + 1) / 2
        }
        let growth = sizes.reduce(0) { $0 + $1 - baseSize }
        if growth > availableGrowth {
            sizes = sizes.map { baseSize + ($0 - baseSize) * availableGrowth / growth }
        }
        return sizes
    }

    // Map a focus between resting icon centers to the same fractional position
    // between their enlarged centers, after centering and screen-edge clamping.
    func screenOffset(at focus: Double, sizes: [Double]) -> Double {
        let growth = sizes.reduce(0) { $0 + $1 - baseSize }
        var precedingGrowth = 0.0
        var previousCenter: Double?
        for index in centers.indices {
            let delta = sizes[index] - baseSize
            let center = centers[index] + precedingGrowth + delta / 2 - bounds.originShift(for: growth)
            if focus <= centers[index] {
                guard index > 0, let previousCenter else { return center }
                let fraction = (focus - centers[index - 1]) / (centers[index] - centers[index - 1])
                return previousCenter + (center - previousCenter) * fraction
            }
            precedingGrowth += delta
            previousCenter = center
        }
        return previousCenter ?? focus
    }

    func focus(for pointer: Double) -> Double {
        guard let first = centers.first, let last = centers.last else { return pointer }
        let firstSizes = sizes(at: first)
        let firstScreen = screenOffset(at: first, sizes: firstSizes)
        if pointer <= firstScreen {
            // Beyond the end centers, preserve the cosine's two-pitch falloff
            // in pointer coordinates. Clamping focus would pin the end icon;
            // inverting the moving off-end geometry can fold the mapping.
            return first + (pointer - firstScreen)
        }
        let lastSizes = sizes(at: last)
        let lastScreen = screenOffset(at: last, sizes: lastSizes)
        if pointer >= lastScreen {
            return last + (pointer - lastScreen)
        }

        // Bounded, deterministic solve over icon centers. No state from the
        // previous frame, Newton overshoot, or pointer-direction dependence.
        var lower = first
        var upper = last
        for _ in 0..<32 {
            let focus = (lower + upper) / 2
            let offset = screenOffset(at: focus, sizes: sizes(at: focus))
            if abs(offset - pointer) < 0.000_000_1 { return focus }
            if offset < pointer { lower = focus } else { upper = focus }
        }
        return (lower + upper) / 2
    }
}
