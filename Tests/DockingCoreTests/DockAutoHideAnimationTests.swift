import XCTest
@testable import DockingCore

final class DockAutoHideAnimationTests: XCTestCase {
    func testNativeDurationQuantizesBeforeApplyingSixtyMilliseconds() {
        XCTAssertEqual(DockAutoHideAnimation.duration(distance: 36), 0.18, accuracy: 1e-12)
        XCTAssertEqual(DockAutoHideAnimation.duration(distance: 48), 0.24, accuracy: 1e-12)
        XCTAssertEqual(DockAutoHideAnimation.duration(distance: 140), 0.30, accuracy: 1e-12)
        XCTAssertEqual(DockAutoHideAnimation.duration(distance: -140), 0.30, accuracy: 1e-12)
    }

    func testReentryReversesFromTheCurrentPositionAndSettles() {
        var animation = DockAutoHideAnimation()
        animation.setHidden(true, distance: 48)
        animation.advance(by: 0.12)
        XCTAssertEqual(animation.fraction, 0.5, accuracy: 1e-7)
        let before = animation.fraction
        animation.setHidden(false, distance: 24)
        XCTAssertEqual(animation.fraction, before)
        animation.advance(by: 1)
        XCTAssertEqual(animation.fraction, 0)
        XCTAssertFalse(animation.isAnimating)
    }

    func testAnimationExitsTowardEachPhysicalScreenEdge() {
        var animation = DockAutoHideAnimation()
        animation.setHidden(true, distance: 48)
        animation.advance(by: 1)
        XCTAssertEqual(animation.offset(distance: 58, position: .bottomCenter), CGSize(width: 0, height: -58))
        XCTAssertEqual(animation.offset(distance: 58, position: .left), CGSize(width: -58, height: 0))
        XCTAssertEqual(animation.offset(distance: 58, position: .right), CGSize(width: 58, height: 0))
    }
}
