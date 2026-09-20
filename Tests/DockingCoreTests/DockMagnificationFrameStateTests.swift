import XCTest
@testable import DockingCore

final class DockMagnificationFrameStateTests: XCTestCase {
    func testIdleOutsideDoesNotRequestWork() {
        var state = DockMagnificationFrameState()
        for _ in 0..<1_000 {
            XCTAssertFalse(state.request(pointerOffset: nil))
            XCTAssertNil(state.takeTargetUpdate())
        }
    }

    func testPointerBurstProducesOneLatestTarget() {
        var state = DockMagnificationFrameState()
        for offset in 0..<1_000 {
            XCTAssertTrue(state.request(pointerOffset: Double(offset)))
        }
        XCTAssertEqual(state.takeTargetUpdate(), .init(pointerOffset: 999))
        XCTAssertNil(state.takeTargetUpdate())
    }

    func testDuplicateEventDoesNotDiscardPendingTarget() {
        var state = DockMagnificationFrameState()
        XCTAssertTrue(state.request(pointerOffset: 120))
        XCTAssertFalse(state.request(pointerOffset: 120))
        XCTAssertEqual(state.takeTargetUpdate(), .init(pointerOffset: 120))
        XCTAssertNil(state.takeTargetUpdate())
    }

    func testStationaryPointerDoesNotResolveTargetWhileSettling() {
        var state = DockMagnificationFrameState()
        _ = state.request(pointerOffset: 120)
        _ = state.takeTargetUpdate()
        for _ in 0..<240 {
            XCTAssertFalse(state.request(pointerOffset: 120))
            XCTAssertNil(state.takeTargetUpdate())
        }
    }

    func testExitIsAnUpdateNotAnAbsentUpdate() {
        var state = DockMagnificationFrameState()
        _ = state.request(pointerOffset: 120)
        _ = state.takeTargetUpdate()
        XCTAssertTrue(state.request(pointerOffset: nil))
        XCTAssertEqual(state.takeTargetUpdate(), .init(pointerOffset: nil))
        XCTAssertFalse(state.request(pointerOffset: nil))
        XCTAssertNil(state.takeTargetUpdate())
    }

    func testReversalAndReentryKeepOnlyLatestInput() {
        var state = DockMagnificationFrameState()
        for offset: Double? in [100, 200, 300, 200, nil, 80] {
            _ = state.request(pointerOffset: offset)
        }
        XCTAssertEqual(state.takeTargetUpdate(), .init(pointerOffset: 80))
        XCTAssertNil(state.takeTargetUpdate())
    }

    func testResetInvalidatesInputAfterLayoutOrDisplayChange() {
        var state = DockMagnificationFrameState()
        _ = state.request(pointerOffset: 120)
        _ = state.takeTargetUpdate()
        _ = state.elapsedTime(timestamp: 0, targetTimestamp: 0.01)
        state = DockMagnificationFrameState()
        XCTAssertNil(state.takeTargetUpdate())
        XCTAssertTrue(state.request(pointerOffset: 120))
        XCTAssertEqual(state.takeTargetUpdate(), .init(pointerOffset: 120))
        XCTAssertEqual(state.elapsedTime(timestamp: 100, targetTimestamp: 100.01), 0.01, accuracy: 1e-10)
    }

    func testResetDropsPendingInput() {
        var state = DockMagnificationFrameState()
        _ = state.request(pointerOffset: 120)
        state = DockMagnificationFrameState()
        XCTAssertNil(state.takeTargetUpdate())
        XCTAssertFalse(state.request(pointerOffset: nil))
    }

    func testPausingPreservesCachedTarget() {
        var state = DockMagnificationFrameState()
        _ = state.request(pointerOffset: 120)
        _ = state.takeTargetUpdate()
        _ = state.elapsedTime(timestamp: 0, targetTimestamp: 0.01)
        state.resetClock()
        XCTAssertFalse(state.request(pointerOffset: 120))
        XCTAssertNil(state.takeTargetUpdate())
        XCTAssertTrue(state.request(pointerOffset: 121))
        XCTAssertEqual(state.takeTargetUpdate(), .init(pointerOffset: 121))
    }

    func testResumeExcludesPausedWallTime() {
        var state = DockMagnificationFrameState()
        _ = state.elapsedTime(timestamp: 0, targetTimestamp: 1.0 / 60)
        state.resetClock()
        XCTAssertEqual(state.elapsedTime(timestamp: 3_600, targetTimestamp: 3_600 + 1.0 / 120),
                       1.0 / 120, accuracy: 1e-10)
    }

    func testSkippedFramesIncludeAllPresentationTime() {
        var state = DockMagnificationFrameState()
        XCTAssertEqual(state.elapsedTime(timestamp: 0, targetTimestamp: 1.0 / 60), 1.0 / 60, accuracy: 1e-10)
        XCTAssertEqual(state.elapsedTime(timestamp: 3.0 / 60, targetTimestamp: 4.0 / 60), 3.0 / 60, accuracy: 1e-10)
    }

    func testRefreshRateChangesUseTargetTimeline() {
        var state = DockMagnificationFrameState()
        let targets = [1.0 / 120, 2.0 / 120, 4.0 / 120, 6.0 / 120, 6.5 / 120]
        var previous = 0.0
        for target in targets {
            let elapsed = state.elapsedTime(timestamp: previous, targetTimestamp: target)
            XCTAssertEqual(elapsed, target - previous, accuracy: 1e-10)
            previous = target
        }
    }

    func testElapsedTimeMatchesAcrossDisplayRates() {
        for framesPerSecond in [60, 120, 240] {
            var state = DockMagnificationFrameState()
            var elapsed = 0.0
            for frame in 1...framesPerSecond {
                elapsed += state.elapsedTime(timestamp: Double(frame - 1) / Double(framesPerSecond),
                                             targetTimestamp: Double(frame) / Double(framesPerSecond))
            }
            XCTAssertEqual(elapsed, 1, accuracy: 1e-10)
        }
    }

    func testHighRateInputIsBoundedByFramesNotEvents() {
        for eventsPerFrame in [1, 8, 67] {
            var state = DockMagnificationFrameState()
            var updates = 0
            for frame in 0..<120 {
                for event in 0..<eventsPerFrame {
                    _ = state.request(pointerOffset: Double(frame * eventsPerFrame + event))
                }
                let latest = Double((frame + 1) * eventsPerFrame - 1)
                XCTAssertFalse(state.request(pointerOffset: latest))
                if let update = state.takeTargetUpdate() {
                    XCTAssertEqual(update.pointerOffset, latest)
                    updates += 1
                }
                XCTAssertNil(state.takeTargetUpdate())
            }
            XCTAssertEqual(updates, 120)
        }
    }

    func testNonfinitePointerReturnsToRestWithoutRepeatedWork() {
        var state = DockMagnificationFrameState()
        XCTAssertFalse(state.request(pointerOffset: .nan))
        _ = state.request(pointerOffset: 120)
        _ = state.takeTargetUpdate()
        XCTAssertTrue(state.request(pointerOffset: .infinity))
        XCTAssertEqual(state.takeTargetUpdate(), .init(pointerOffset: nil))
        XCTAssertFalse(state.request(pointerOffset: -.infinity))
        XCTAssertFalse(state.request(pointerOffset: .nan))
    }
}
