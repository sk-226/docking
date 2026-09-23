import XCTest
@testable import DockingCore

final class DockMagnificationAnimationTests: XCTestCase {
    func testNativeDurationReferenceValues() {
        for (growth, duration) in [(1.0, 0.018), (36.0, 0.124), (64.0, 0.147), (92.0, 0.162), (104.0, 0.167)] {
            var animation = DockMagnificationAnimation()
            animation.setActive(true, maximumGrowth: growth)
            XCTAssertEqual(animation.duration, duration, accuracy: 1e-12)
            animation.advance(by: duration)
            XCTAssertEqual(animation.value, 1)
            XCTAssertFalse(animation.isAnimating)
            animation.setActive(false, maximumGrowth: growth)
            XCTAssertEqual(animation.duration, duration, accuracy: 1e-12)
        }
    }

    func testCosineQuarterHalfAndThreeQuarterProgress() {
        for (fraction, expected) in [(0.25, 0.14644661713388152), (0.5, 0.500000021855695), (0.75, 0.8535534137747404)] {
            var animation = DockMagnificationAnimation()
            animation.setActive(true, maximumGrowth: 64)
            animation.advance(by: animation.duration * fraction)
            XCTAssertEqual(animation.value, expected, accuracy: 1e-8)
        }
    }

    func testRepeatedActiveInputDoesNotRestartEntry() {
        var animation = DockMagnificationAnimation()
        animation.setActive(true, maximumGrowth: 92)
        for _ in 0..<20 {
            animation.setActive(true, maximumGrowth: 92)
            animation.advance(by: 0.01)
        }
        XCTAssertEqual(animation.value, 1)
        XCTAssertFalse(animation.isAnimating)
    }

    func testEqualElapsedTimeAcrossRefreshRatesAndSkippedFrames() {
        var values: [Double] = []
        for rate in [60, 120, 240] {
            var animation = DockMagnificationAnimation()
            animation.setActive(true, maximumGrowth: 92)
            for _ in 0..<(rate / 10) { animation.advance(by: 1 / Double(rate)) }
            values.append(animation.value)
        }
        var skipped = DockMagnificationAnimation()
        skipped.setActive(true, maximumGrowth: 92)
        skipped.advance(by: 0.1)
        for value in values { XCTAssertEqual(value, skipped.value, accuracy: 1e-12) }
    }

    func testExitUsesRemainingSizeDifferenceAndDoesNotJump() {
        var animation = DockMagnificationAnimation()
        animation.setActive(true, maximumGrowth: 64)
        animation.advance(by: animation.duration / 2)
        let before = animation.value
        animation.setActive(false, maximumGrowth: 64)
        XCTAssertEqual(animation.value, before)
        XCTAssertEqual(animation.duration, 0.119, accuracy: 1e-12)
        animation.advance(by: animation.duration)
        XCTAssertEqual(animation.value, 0)
        XCTAssertFalse(animation.isAnimating)
        animation.advance(by: 60)
        XCTAssertEqual(animation.value, 0)
    }

    func testZeroElapsedAndRestingInputDoNotStartMotion() {
        var animation = DockMagnificationAnimation()
        animation.setActive(false, maximumGrowth: 92)
        animation.advance(by: 60)
        XCTAssertEqual(animation.value, 0)
        XCTAssertFalse(animation.isAnimating)
        animation.setActive(true, maximumGrowth: 92)
        animation.advance(by: 0)
        XCTAssertEqual(animation.value, 0)
    }
}
