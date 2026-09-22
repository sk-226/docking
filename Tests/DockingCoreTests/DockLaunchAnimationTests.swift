import XCTest
@testable import DockingCore

final class DockLaunchAnimationTests: XCTestCase {
    func testNativeLaunchBounceSamples() {
        var animation = DockLaunchAnimation()
        XCTAssertEqual(animation.value, 0)
        animation.advance(by: 0.175)
        XCTAssertEqual(animation.value, 0.75, accuracy: 1e-6)
        animation.advance(by: 0.175)
        XCTAssertEqual(animation.value, 1)
        animation.advance(by: 0.175)
        XCTAssertEqual(animation.value, 0.75, accuracy: 1e-6)
        animation.advance(by: 0.175)
        XCTAssertEqual(animation.value, 0, accuracy: 1e-6)
        XCTAssertEqual(DockLaunchAnimation.height(iconSize: 48), 14, accuracy: 1e-6)
    }

    func testReadyApplicationFinishesAtTheGround() {
        var animation = DockLaunchAnimation()
        animation.advance(by: 0.2)
        let before = animation.value
        animation.finish()
        XCTAssertEqual(animation.value, before)
        animation.advance(by: 0.499)
        XCTAssertTrue(animation.isAnimating)
        animation.advance(by: 0.002)
        XCTAssertFalse(animation.isAnimating)
        XCTAssertEqual(animation.value, 0)
    }

    func testLaunchTimeoutAndAllOrientations() {
        var animation = DockLaunchAnimation()
        animation.advance(by: 120)
        XCTAssertFalse(animation.isAnimating)
        XCTAssertEqual(animation.value, 0)
        XCTAssertEqual(DockLaunchAnimation.offset(value: 1, iconSize: 48, position: .bottomCenter), CGSize(width: 0, height: -14))
        XCTAssertEqual(DockLaunchAnimation.offset(value: 1, iconSize: 48, position: .left), CGSize(width: 14, height: 0))
        XCTAssertEqual(DockLaunchAnimation.offset(value: 1, iconSize: 48, position: .right), CGSize(width: -14, height: 0))
    }
}
