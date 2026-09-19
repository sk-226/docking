import Foundation
import XCTest
@testable import DockingCore

final class DockMagnificationTests: XCTestCase {
    private func settings(size: Double = 36, maximum: Double = 128) -> DockingSettings {
        var settings = DockingSettings.default
        settings.iconSize = size
        settings.magnificationSize = maximum
        settings.calendarEnabled = false
        settings.weatherEnabled = false
        return settings
    }

    private func lens(_ base: DockLayoutMetrics, settings: DockingSettings,
                      bounds: DockMagnificationBounds = DockMagnificationBounds(),
                      available: Double = .infinity) -> DockMagnificationLens {
        DockMagnificationLens(centers: base.iconCenters, baseSize: settings.iconSize,
                              radius: (settings.iconSize + settings.spacing) * 2,
                              maximumGrowth: max(0, settings.magnificationSize - settings.iconSize),
                              availableGrowth: min(available, bounds.leading + bounds.trailing), bounds: bounds)
    }

    private func presentedCenter(_ index: Int, _ metrics: DockLayoutMetrics, baseSize: Double) -> Double {
        metrics.iconCenters[index] - metrics.originShift
            + metrics.iconSizes.prefix(index).reduce(0) { $0 + $1 - baseSize }
            + (metrics.iconSizes[index] - baseSize) / 2
    }

    func testSubIconSweepKeepsInteriorOriginAndWidthConstant() {
        for position in DockPosition.allCases {
            var settings = settings()
            settings.dockPosition = position
            let base = DockLayout.metrics(itemCount: 16, settings: settings)
            let baseLength = position.isVertical ? base.panelSize.height : base.panelSize.width
            let offsets = (0...400).map {
                base.iconCenters[6] + Double($0) / 400 * (base.iconCenters[7] - base.iconCenters[6])
            }
            var moving = DockLayout.metrics(itemCount: 16, settings: settings, pointerOffset: offsets[0])
            for pointer in offsets + offsets.reversed() {
                let target = DockLayout.metrics(itemCount: 16, settings: settings, pointerOffset: pointer)
                // Exact reproduction from MAGNIFICATION_HANDOFF.md: 16 icons,
                // size 36 -> 128. Old targets oscillated by nearly 12 points.
                XCTAssertEqual(target.originShift, 92, accuracy: 0.000_001)
                let length = position.isVertical ? target.panelSize.height : target.panelSize.width
                XCTAssertEqual(length - baseLength, 184, accuracy: 0.000_001)
                moving = moving.approaching(target, elapsed: 1.0 / 120)
                XCTAssertEqual(moving.originShift, 92, accuracy: 0.000_001)
            }
        }
    }

    func testEveryIconCenterIsTargetableIncludingEndsAndDivider() {
        let boundsCases = [DockMagnificationBounds(), DockMagnificationBounds(leading: 0, trailing: 1000),
                           DockMagnificationBounds(leading: 1000, trailing: 0),
                           DockMagnificationBounds(leading: 9, trailing: 120),
                           DockMagnificationBounds(leading: 40, trailing: 17)]
        for size in [24.0, 36, 72] {
            let settings = settings(size: size)
            for count in [1, 2, 3, 16] {
                let divider = count > 1 ? count / 2 : nil
                let base = DockLayout.metrics(itemCount: count, settings: settings, separatedRunningStart: divider)
                for bounds in boundsCases {
                    let lens = lens(base, settings: settings, bounds: bounds)
                    for index in base.iconCenters.indices {
                        let expectedSizes = lens.sizes(at: base.iconCenters[index])
                        let pointer = lens.screenOffset(at: base.iconCenters[index], sizes: expectedSizes)
                        let target = DockLayout.metrics(itemCount: count, settings: settings, separatedRunningStart: divider,
                                                        pointerOffset: pointer, magnificationBounds: bounds)
                        XCTAssertEqual(presentedCenter(index, target, baseSize: size), pointer, accuracy: 0.000_001)
                        for (actual, expected) in zip(target.iconSizes, expectedSizes) {
                            XCTAssertEqual(actual, expected, accuracy: 0.000_001)
                        }
                    }
                }
            }
        }
    }

    func testCenterMappingIsMonotoneAcrossSupportedSizesAndClamps() {
        let boundsCases = [DockMagnificationBounds(), DockMagnificationBounds(leading: 0, trailing: 1000),
                           DockMagnificationBounds(leading: 1000, trailing: 0),
                           DockMagnificationBounds(leading: 8, trailing: 90)]
        for size in stride(from: 24.0, through: 72.0, by: 4) {
            let settings = settings(size: size)
            for count in [2, 3, 16] {
                for divider in [nil, Optional(1), Optional(count / 2)] {
                    let base = DockLayout.metrics(itemCount: count, settings: settings, separatedRunningStart: divider)
                    for bounds in boundsCases {
                        for available in [15.0, 100.0, Double.infinity] {
                            let lens = lens(base, settings: settings, bounds: bounds, available: available)
                            var previous = -Double.infinity
                            for sample in 0...300 {
                                let focus = base.iconCenters[0]
                                    + (base.iconCenters[count - 1] - base.iconCenters[0]) * Double(sample) / 300
                                let screen = lens.screenOffset(at: focus, sizes: lens.sizes(at: focus))
                                XCTAssertGreaterThan(screen, previous, "center mapping must not fold at size \(size)")
                                previous = screen
                            }
                        }
                    }
                }
            }
        }
    }

    func testInverseRoundTripAndDirectionIndependence() {
        let settings = settings(size: 24)
        let base = DockLayout.metrics(itemCount: 16, settings: settings, separatedRunningStart: 8)
        let bounds = DockMagnificationBounds(leading: 3, trailing: 200)
        let lens = lens(base, settings: settings, bounds: bounds)
        let focusOffsets = (0...600).map {
            base.iconCenters[0] + (base.iconCenters[15] - base.iconCenters[0]) * Double($0) / 600
        }
        for focus in focusOffsets + focusOffsets.reversed() {
            let pointer = lens.screenOffset(at: focus, sizes: lens.sizes(at: focus))
            XCTAssertEqual(lens.focus(for: pointer), focus, accuracy: 0.000_002)
        }
    }

    func testEndExtensionsAreContinuousAndFadeInsteadOfPinningLastIcon() {
        for count in [1, 16] {
            let settings = settings(size: 24)
            let base = DockLayout.metrics(itemCount: count, settings: settings)
            let lens = lens(base, settings: settings)
            for (index, direction) in [(0, -1.0), (count - 1, 1.0)] {
                let focus = base.iconCenters[index]
                let pointer = lens.screenOffset(at: focus, sizes: lens.sizes(at: focus))
                let before = DockLayout.metrics(itemCount: count, settings: settings, pointerOffset: pointer - 0.000_01)
                let after = DockLayout.metrics(itemCount: count, settings: settings, pointerOffset: pointer + 0.000_01)
                for (left, right) in zip(before.iconSizes, after.iconSizes) {
                    XCTAssertEqual(left, right, accuracy: 0.000_1)
                }
                let outside = pointer + direction * lens.radius * 1.01
                XCTAssertEqual(DockLayout.metrics(itemCount: count, settings: settings, pointerOffset: outside), base)
            }
        }
    }

    func testClampedScreenGeometryAndFixedCanvasOnEveryEdge() {
        // A translated screen catches accidental use of global origins. Test
        // bottom-left/right as genuinely edge-aligned docks, not centered ones.
        let limits = CGRect(x: -1500, y: 200, width: 1000, height: 760)
        for position in DockPosition.allCases {
            var settings = settings()
            settings.dockPosition = position
            settings.calendarEnabled = true
            settings.weatherEnabled = true
            for count in [0, 1, 16, 70] {
                let length = position.isVertical ? limits.height : limits.width
                let base = DockLayout.metrics(itemCount: count, settings: settings, maximumLength: length)
                var baseFrame = CGRect(x: limits.midX - base.scaledPanelSize.width / 2,
                                       y: limits.midY - base.scaledPanelSize.height / 2,
                                       width: base.scaledPanelSize.width, height: base.scaledPanelSize.height)
                switch position {
                case .left: baseFrame.origin.x = limits.minX
                case .right: baseFrame.origin.x = limits.maxX - baseFrame.width
                case .bottomCenter: baseFrame.origin.y = limits.minY
                case .bottomLeft: baseFrame.origin = CGPoint(x: limits.minX, y: limits.minY)
                case .bottomRight: baseFrame.origin = CGPoint(x: limits.maxX - baseFrame.width, y: limits.minY)
                }
                let bounds = DockPanelGeometry.magnificationBounds(baseFrame: baseFrame, position: position,
                                                                   limits: limits, scale: base.scale)
                let canvas = DockPanelGeometry.canvasFrame(baseFrame: baseFrame, resting: base, settings: settings, limits: limits)
                var moving = base
                let offsets = Array(stride(from: -150.0, through: length / base.scale + 150, by: 7))
                for pointer in offsets + offsets.reversed() {
                    let target = DockLayout.metrics(itemCount: count, settings: settings, maximumLength: length,
                                                    pointerOffset: pointer, magnificationBounds: bounds)
                    let targetFrame = DockPanelGeometry.contentFrame(baseFrame: baseFrame, metrics: target, position: position, limits: limits)
                    let actualShift = position.isVertical ? targetFrame.maxY - baseFrame.maxY : baseFrame.minX - targetFrame.minX
                    XCTAssertEqual(actualShift, target.originShift * base.scale, accuracy: 0.000_001,
                                   "post-layout clamping must not shift the hover target")
                    moving = moving.approaching(target, elapsed: 1.0 / 120)
                    let frame = DockPanelGeometry.contentFrame(baseFrame: baseFrame, metrics: moving, position: position, limits: limits)
                    for container in [canvas, limits] {
                        XCTAssertGreaterThanOrEqual(frame.minX, container.minX - 0.001)
                        XCTAssertGreaterThanOrEqual(frame.minY, container.minY - 0.001)
                        XCTAssertLessThanOrEqual(frame.maxX, container.maxX + 0.001)
                        XCTAssertLessThanOrEqual(frame.maxY, container.maxY + 0.001)
                    }
                }
                for _ in 0..<120 { moving = moving.approaching(base, elapsed: 1.0 / 120) }
                XCTAssertEqual(moving, base)
                let outside = CGPoint(x: canvas.minX + 1, y: canvas.maxY - 1)
                if !baseFrame.contains(outside) {
                    XCTAssertFalse(DockPanelHitGeometry.contains(outside, panelFrame: baseFrame, position: position))
                }
            }
        }
    }

    func testVerticalBoundsFollowTopToBottomOrderAndScale() {
        let limits = CGRect(x: 100, y: 200, width: 900, height: 700)
        let frame = CGRect(x: 300, y: 250, width: 50, height: 500)
        let vertical = DockPanelGeometry.magnificationBounds(baseFrame: frame, position: .right, limits: limits, scale: 0.5)
        XCTAssertEqual(vertical.leading, 300)
        XCTAssertEqual(vertical.trailing, 100)
        let horizontal = DockPanelGeometry.magnificationBounds(baseFrame: frame, position: .bottomLeft, limits: limits, scale: 0.5)
        XCTAssertEqual(horizontal.leading, 400)
        XCTAssertEqual(horizontal.trailing, 1300)
    }

    func testTimingReversalAndExactIdleSettlement() {
        let settings = settings()
        let base = DockLayout.metrics(itemCount: 16, settings: settings)
        let left = DockLayout.metrics(itemCount: 16, settings: settings, pointerOffset: base.iconCenters[3] + 9)
        let right = DockLayout.metrics(itemCount: 16, settings: settings, pointerOffset: base.iconCenters[12] - 7)
        var moving = left
        for target in [right, left, right, left] {
            for _ in 0..<12 {
                moving = moving.approaching(target, elapsed: 1.0 / 60)
                XCTAssertEqual(moving.originShift, 92, accuracy: 0.000_001)
                XCTAssertEqual(moving.panelSize.width, left.panelSize.width, accuracy: 0.000_001)
            }
        }
        var sixtyHz = base
        var oneTwentyHz = base
        var twoFortyHz = base
        for _ in 0..<6 { sixtyHz = sixtyHz.approaching(left, elapsed: 1.0 / 60) }
        for _ in 0..<12 { oneTwentyHz = oneTwentyHz.approaching(left, elapsed: 1.0 / 120) }
        for _ in 0..<24 { twoFortyHz = twoFortyHz.approaching(left, elapsed: 1.0 / 240) }
        for other in [oneTwentyHz, twoFortyHz] {
            for (a, b) in zip(sixtyHz.iconSizes, other.iconSizes) { XCTAssertEqual(a, b, accuracy: 0.000_001) }
            XCTAssertEqual(sixtyHz.originShift, other.originShift, accuracy: 0.000_001)
        }
        for _ in 0..<60 { moving = moving.approaching(base, elapsed: 1.0 / 60) }
        XCTAssertEqual(moving, base, "exact equality lets the display link pause")
    }

    func testNoMagnificationForDisabledEmptyOrNoRoom() {
        var settings = settings()
        let base = DockLayout.metrics(itemCount: 16, settings: settings)
        settings.magnificationEnabled = false
        XCTAssertEqual(DockLayout.metrics(itemCount: 16, settings: settings, pointerOffset: 300), base)
        settings.magnificationEnabled = true
        for pointer in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(DockLayout.metrics(itemCount: 16, settings: settings, pointerOffset: pointer), base)
        }
        XCTAssertEqual(DockLayout.metrics(itemCount: 16, settings: settings, pointerOffset: 300,
                                          magnificationBounds: DockMagnificationBounds(leading: 0, trailing: 0)), base)
        settings.magnificationSize = 24
        XCTAssertEqual(DockLayout.metrics(itemCount: 16, settings: settings, pointerOffset: 300), base)
        let empty = DockLayout.metrics(itemCount: 0, settings: settings)
        XCTAssertEqual(DockLayout.metrics(itemCount: 0, settings: settings, pointerOffset: 300), empty)
        for position in DockPosition.allCases {
            settings.dockPosition = position
            settings.magnificationSize = 128
            let crowded = DockLayout.metrics(itemCount: 70, settings: settings, maximumLength: 760)
            XCTAssertEqual(DockLayout.metrics(itemCount: 70, settings: settings, maximumLength: 760, pointerOffset: 300), crowded)
        }
    }

    func testWidgetsAndGlassKeepTheirRestingThickness() {
        for position in DockPosition.allCases {
            var settings = settings()
            settings.dockPosition = position
            settings.calendarEnabled = true
            settings.weatherEnabled = true
            let base = DockLayout.metrics(itemCount: 7, settings: settings)
            let target = DockLayout.metrics(itemCount: 7, settings: settings, pointerOffset: base.iconCenters[3])
            XCTAssertEqual(target.iconSizes[3], 128)
            XCTAssertEqual(target.iconSizes[0], settings.iconSize)
            XCTAssertEqual(target.iconSizes[6], settings.iconSize)
            XCTAssertEqual(target.iconSizes[2], target.iconSizes[4], accuracy: 0.000_001)
            XCTAssertEqual(position.isVertical ? base.surfaceSize.width : base.surfaceSize.height,
                           position.isVertical ? target.surfaceSize.width : target.surfaceSize.height)
        }
    }
}
