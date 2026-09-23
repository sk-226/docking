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
                              maximumGrowth: max(0, settings.magnificationSize - settings.iconSize),
                              availableGrowth: min(available, bounds.leading + bounds.trailing), bounds: bounds)
    }

    private func presentedCenter(_ index: Int, _ metrics: DockLayoutMetrics, baseSize: Double) -> Double {
        metrics.iconCenters[index] + metrics.iconLeadingInsets.prefix(index + 1).reduce(0, +)
            + metrics.iconSizes.prefix(index).reduce(0) { $0 + $1 - baseSize }
            + (metrics.iconSizes[index] - baseSize) / 2 - metrics.originShift
    }

    func testNativeCoordinateWarpReferenceWidths() {
        let centers = [-144.0, -108, -72, -36, 0, 36, 72, 108, 144]
        let lens = DockMagnificationLens(centers: centers, baseSize: 36, maximumGrowth: 92,
                                         availableGrowth: .infinity, bounds: .init())
        let expected = [36.0, 42.056013048760974, 81.99999767821596, 115.67433647792706, 128,
                        115.67433647792706, 81.99999767821596, 42.056013048760974, 36]
        for (actual, reference) in zip(lens.geometry(at: 0).sizes, expected) {
            XCTAssertEqual(actual, reference, accuracy: 1e-6)
        }
    }

    func testGapExpansionAccountsForTheWholeCoordinateWarp() {
        let settings = settings()
        let base = DockLayout.metrics(itemCount: 16, settings: settings, documentStart: 8)
        let target = DockLayout.metrics(itemCount: 16, settings: settings, documentStart: 8,
                                        pointerOffset: base.iconCenters[7])
        XCTAssertGreaterThan(target.iconLeadingInsets.reduce(0, +), 0)
        let iconGrowth = target.iconSizes.reduce(0) { $0 + $1 - settings.iconSize }
        let gapGrowth = target.iconLeadingInsets.reduce(0, +)
        XCTAssertEqual(iconGrowth + gapGrowth, target.panelSize.width - base.panelSize.width, accuracy: 1e-9)
        XCTAssertEqual(target.panelSize.width - base.panelSize.width, 355.46069440980796, accuracy: 1e-6)
    }

    func testNativeFocusUsesPointerAndClampsToBarEdges() {
        let base = DockLayout.metrics(itemCount: 16, settings: settings())
        let lens = lens(base, settings: settings())
        XCTAssertEqual(lens.focus(for: -100), base.iconCenters[0] - 18)
        XCTAssertEqual(lens.focus(for: 10_000), base.iconCenters[15] + 18)
        for pointer in stride(from: base.iconCenters[0], through: base.iconCenters[15], by: 0.5) {
            XCTAssertEqual(lens.focus(for: pointer), pointer)
        }
    }

    func testNativeEndIconKeepsItsRestingCenterDuringEntry() {
        let settings = settings()
        let base = DockLayout.metrics(itemCount: 16, settings: settings)
        for index in [0, 1, 6, 14, 15] {
            for progress in [0.1, 0.25, 0.5, 0.75, 1] {
                let target = DockLayout.metrics(itemCount: 16, settings: settings,
                                                pointerOffset: base.iconCenters[index], magnificationProgress: progress)
                XCTAssertEqual(presentedCenter(index, target, baseSize: 36), base.iconCenters[index], accuracy: 1e-6)
                XCTAssertEqual(target.iconSizes[index], 36 + 92 * progress, accuracy: 1e-6)
            }
        }
        let first = DockLayout.metrics(itemCount: 16, settings: settings, pointerOffset: base.iconCenters[0])
        XCTAssertEqual(first.originShift, 46, accuracy: 1e-6)
        XCTAssertEqual(first.panelSize.width - base.panelSize.width, 223.73034720490398, accuracy: 1e-6)
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
            for pointer in offsets + offsets.reversed() {
                let target = DockLayout.metrics(itemCount: 16, settings: settings, pointerOffset: pointer)
                XCTAssertEqual(target.originShift, 177.73034720490398, accuracy: 0.000_001)
                let length = position.isVertical ? target.panelSize.height : target.panelSize.width
                XCTAssertEqual(length - baseLength, 355.46069440980796, accuracy: 0.000_001)
            }
        }
    }

    func testNativeFocusHasNoHistoryOrInverseCorrection() {
        let settings = settings()
        let base = DockLayout.metrics(itemCount: 16, settings: settings, documentStart: 8)
        for pointer in stride(from: base.iconCenters[0], through: base.iconCenters[15], by: 0.5) {
            let expected = lens(base, settings: settings).geometry(at: pointer)
            let actual = DockLayout.metrics(itemCount: 16, settings: settings, documentStart: 8,
                                           pointerOffset: pointer)
            XCTAssertEqual(actual.iconSizes, expected.sizes)
            XCTAssertEqual(actual.originShift, expected.originShift)
        }
    }

    func testResidenceDepthDoesNotCollapseBetweenIcons() {
        let settings = settings()
        let base = DockLayout.metrics(itemCount: 16, settings: settings)
        let centered = DockLayout.metrics(itemCount: 16, settings: settings, pointerOffset: base.iconCenters[6])
        let between = DockLayout.metrics(itemCount: 16, settings: settings,
                                         pointerOffset: (base.iconCenters[6] + base.iconCenters[7]) / 2)
        XCTAssertLessThan(between.panelSize.height, centered.panelSize.height)
        XCTAssertEqual(between.residenceThickness, centered.residenceThickness)
        XCTAssertEqual(centered.residenceThickness, 144)
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
            for count in [0, 1, 2, 16, 70] {
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
                let offsets = Array(stride(from: -150.0, through: length / base.scale + 150, by: 7))
                for (sample, pointer) in (offsets + offsets.reversed()).enumerated() {
                    let progress = Double(sample % 11) / 10
                    let target = DockLayout.metrics(itemCount: count, settings: settings, maximumLength: length,
                                                    pointerOffset: pointer, magnificationProgress: progress, magnificationBounds: bounds)
                    let targetFrame = DockPanelGeometry.contentFrame(baseFrame: baseFrame, metrics: target, position: position, limits: limits)
                    let actualShift = position.isVertical ? targetFrame.maxY - baseFrame.maxY : baseFrame.minX - targetFrame.minX
                    XCTAssertEqual(actualShift, target.originShift * base.scale, accuracy: 0.000_001,
                                   "post-layout clamping must not shift the hover target")
                    let frame = DockPanelGeometry.contentFrame(baseFrame: baseFrame, metrics: target, position: position, limits: limits)
                    for container in [canvas, limits] {
                        XCTAssertGreaterThanOrEqual(frame.minX, container.minX - 0.001)
                        XCTAssertGreaterThanOrEqual(frame.minY, container.minY - 0.001)
                        XCTAssertLessThanOrEqual(frame.maxX, container.maxX + 0.001)
                        XCTAssertLessThanOrEqual(frame.maxY, container.maxY + 0.001)
                    }
                }
                XCTAssertEqual(DockLayout.metrics(itemCount: count, settings: settings, maximumLength: length,
                                                  pointerOffset: 100, magnificationProgress: 0, magnificationBounds: bounds), base)
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
        var animation = DockMagnificationAnimation()
        animation.setActive(true, maximumGrowth: 92)
        animation.advance(by: 0.08)
        let midEntry = animation.value
        animation.setActive(false, maximumGrowth: 92)
        XCTAssertEqual(animation.value, midEntry)
        animation.advance(by: 0.03)
        XCTAssertLessThan(animation.value, midEntry)
        animation.setActive(true, maximumGrowth: 92)
        animation.advance(by: 1)
        XCTAssertEqual(animation.value, 1)
        animation.setActive(false, maximumGrowth: 92)
        animation.advance(by: 1)
        XCTAssertFalse(animation.isAnimating)
        let settled = DockLayout.metrics(itemCount: 16, settings: settings, pointerOffset: base.iconCenters[6],
                                         magnificationProgress: animation.value)
        XCTAssertEqual(settled, base)
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
    }

    func testCrowdedDockReservesMagnificationWithoutChangingScaleDuringTracking() {
        for position in DockPosition.allCases {
            var settings = settings()
            settings.dockPosition = position
            settings.calendarEnabled = true
            settings.weatherEnabled = true
            for count in [32, 70] {
                let limit = position.isVertical ? 760.0 : 1280.0
                let base = DockLayout.metrics(itemCount: count, settings: settings, documentStart: count - 2,
                                             runningSectionStart: count - 3, maximumLength: limit)
                let length = position.isVertical ? base.scaledPanelSize.height : base.scaledPanelSize.width
                XCTAssertLessThan(length, limit)
                XCTAssertLessThan(base.scale, 1)
                for index in [0, count / 2, count - 1] {
                    let hovered = DockLayout.metrics(itemCount: count, settings: settings, documentStart: count - 2,
                                                     runningSectionStart: count - 3, maximumLength: limit,
                                                     pointerOffset: base.iconCenters[index])
                    XCTAssertEqual(hovered.iconSizes[index], settings.magnificationSize, accuracy: 1e-6)
                    XCTAssertEqual(hovered.scale, base.scale)
                    let expandedLength = position.isVertical ? hovered.scaledPanelSize.height : hovered.scaledPanelSize.width
                    XCTAssertLessThanOrEqual(expandedLength, limit + 1e-6)
                    XCTAssertGreaterThan(expandedLength, length)
                }
            }
        }
    }

    func testWidgetsAndGlassKeepTheirRestingThickness() {
        for position in DockPosition.allCases {
            var settings = settings()
            settings.dockPosition = position
            settings.calendarEnabled = true
            settings.weatherEnabled = true
            let base = DockLayout.metrics(itemCount: 9, settings: settings)
            let target = DockLayout.metrics(itemCount: 9, settings: settings, pointerOffset: base.iconCenters[4])
            XCTAssertEqual(target.iconSizes[4], 128, accuracy: 0.000_001)
            XCTAssertEqual(target.iconSizes[0], settings.iconSize)
            XCTAssertEqual(target.iconSizes[8], settings.iconSize)
            XCTAssertEqual(target.iconSizes[3], target.iconSizes[5], accuracy: 0.000_001)
            XCTAssertEqual(position.isVertical ? base.surfaceSize.width : base.surfaceSize.height,
                           position.isVertical ? target.surfaceSize.width : target.surfaceSize.height)
        }
    }
}
