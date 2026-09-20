import Foundation
import XCTest
@testable import DockingCore

final class DockEdgeIntentTests: XCTestCase {
    @discardableResult
    private func move(_ intent: inout DockEdgeIntent, key: String? = "A",
                      position: DockPosition = .bottomCenter, x: Double = 100, y: Double = 0,
                      dx: Double = 0, dy: Double = 0, at time: TimeInterval = 1) -> Bool {
        intent.update(targetKey: key, position: position, location: CGPoint(x: x, y: y),
                      delta: CGSize(width: dx, height: dy), now: time)
    }

    private func canReveal(_ intent: DockEdgeIntent, x: Double = 100) -> Bool {
        intent.canReveal(targetKey: "A", position: .bottomCenter, location: CGPoint(x: x, y: 0))
    }

    func testArrivingAtEdgeIsNotItselfAPush() {
        var intent = DockEdgeIntent()
        XCTAssertFalse(move(&intent, dy: 500))
        XCTAssertFalse(canReveal(intent))
    }

    func testStationaryContactNeverArmsEvenAfterLongDwell() {
        var intent = DockEdgeIntent()
        move(&intent, dy: 100)
        for time in [2.0, 10, 60] {
            XCTAssertFalse(move(&intent, at: time))
        }
    }

    func testContinuingOutwardAfterContactArmsAtTravelThreshold() {
        var intent = DockEdgeIntent()
        move(&intent, dy: 100)
        XCTAssertFalse(move(&intent, dy: 2, at: 1.01))
        XCTAssertFalse(move(&intent, dy: 2, at: 1.02))
        XCTAssertTrue(move(&intent, dy: 1, at: 1.03))
        XCTAssertTrue(canReveal(intent))
        XCTAssertTrue(move(&intent, at: 2)) // Holding still during the reveal delay is allowed.
    }

    func testFractionalMotionMustReachFivePointsBeforeDelayedReveal() {
        var intent = DockEdgeIntent()
        move(&intent)
        XCTAssertFalse(move(&intent, dy: 4.75, at: 1.01))
        XCTAssertFalse(canReveal(intent))
        XCTAssertFalse(move(&intent, at: 1.02))
        XCTAssertTrue(move(&intent, dy: 0.25, at: 1.03))
        XCTAssertTrue(canReveal(intent))
    }

    func testPushUsesDistanceNotEventCount() {
        for steps in [1, 6, 24, 60] {
            var intent = DockEdgeIntent()
            move(&intent)
            for index in 1...steps {
                move(&intent, dy: 5.01 / Double(steps), at: 1 + Double(index) * 0.2 / Double(steps))
            }
            XCTAssertTrue(canReveal(intent), "steps: \(steps)")
        }
    }

    func testSlidingAlongBottomDoesNotReveal() {
        var intent = DockEdgeIntent()
        move(&intent, dy: 50)
        for index in 1...20 {
            XCTAssertFalse(move(&intent, x: 100 + Double(index), dx: 1, dy: 0.1,
                                at: 1 + Double(index) * 0.01))
        }
    }

    func testDirectionAndLateralDriftCancelAlreadyArmedGesture() {
        for delta in [CGSize(width: 2, height: 0), CGSize(width: 0, height: -0.1)] {
            var intent = DockEdgeIntent()
            move(&intent)
            XCTAssertTrue(move(&intent, dy: 5, at: 1.01))
            XCTAssertFalse(move(&intent, dx: delta.width, dy: delta.height, at: 1.02))
            XCTAssertFalse(canReveal(intent))
        }
        var intent = DockEdgeIntent()
        move(&intent)
        move(&intent, dy: 5, at: 1.01)
        XCTAssertFalse(canReveal(intent, x: 109)) // Also checked when the delayed callback runs.
        XCTAssertFalse(move(&intent, x: 109, dy: 2, at: 1.02))
    }

    func testInterruptedSmallMovementsDoNotAccumulateForever() {
        var intent = DockEdgeIntent()
        move(&intent)
        for time in [2.0, 3, 4, 5] {
            XCTAssertFalse(move(&intent, dy: 2, at: time))
        }
        XCTAssertFalse(canReveal(intent))
    }

    func testLeavingAndReenteringNeedsANewPush() {
        var intent = DockEdgeIntent()
        move(&intent)
        move(&intent, dy: 5, at: 1.01)
        XCTAssertFalse(move(&intent, key: nil, y: 4, at: 1.02))
        XCTAssertFalse(move(&intent, dy: 100, at: 1.03))
        XCTAssertTrue(move(&intent, dy: 5, at: 1.04))
    }

    func testDifferentDisplayCannotInheritTravel() {
        var intent = DockEdgeIntent()
        move(&intent)
        move(&intent, dy: 5, at: 1.01)
        XCTAssertFalse(move(&intent, key: "B", x: 1500, dy: 100, at: 1.02))
        XCTAssertFalse(canReveal(intent))
        XCTAssertFalse(move(&intent, key: "A", dy: 100, at: 1.03))
    }

    func testInputOrConfigurationResetDiscardsPendingIntent() {
        var intent = DockEdgeIntent()
        move(&intent)
        move(&intent, dy: 5, at: 1.01)
        intent.reset()
        XCTAssertFalse(canReveal(intent))
        XCTAssertFalse(move(&intent, dy: 100, at: 1.02))
        XCTAssertTrue(move(&intent, dy: 5, at: 1.03))
    }

    func testOneRevealPerContinuousContact() {
        var intent = DockEdgeIntent()
        move(&intent)
        move(&intent, dy: 5, at: 1.01)
        intent.didReveal(targetKey: "A")
        for time in [1.1, 1.2, 2, 5] {
            XCTAssertFalse(move(&intent, dy: 100, at: time))
        }
        XCTAssertFalse(canReveal(intent))
        move(&intent, key: nil, at: 6)
        move(&intent, at: 6.1)
        XCTAssertTrue(move(&intent, dy: 5, at: 6.2))
    }

    func testConsumptionSurvivesTargetRebuildDuringReveal() {
        var intent = DockEdgeIntent()
        move(&intent)
        move(&intent, dy: 5, at: 1.01)
        intent.reset() // The reveal callback can rebuild triggers on the new display.
        intent.didReveal(targetKey: "A")
        XCTAssertFalse(move(&intent, dy: 100, at: 1.02))
    }

    func testOutwardAxesForEveryDockPosition() {
        for position in DockPosition.allCases {
            var intent = DockEdgeIntent()
            move(&intent, position: position, x: -1500, y: 800)
            let dx: Double = position == .left ? -5 : (position == .right ? 5 : 0)
            let dy: Double = position.isBottom ? 5 : 0
            XCTAssertTrue(move(&intent, position: position, x: -1500, y: 800, dx: dx, dy: dy, at: 1.01))
            XCTAssertFalse(move(&intent, position: position, x: -1500, y: 800, dx: -dx, dy: -dy, at: 1.02))
        }
    }

    func testInvalidMotionClearsIntent() {
        for delta in [Double.nan, .infinity, -.infinity] {
            var intent = DockEdgeIntent()
            move(&intent)
            move(&intent, dy: 5, at: 1.01)
            XCTAssertFalse(move(&intent, dy: delta, at: 1.02))
            XCTAssertFalse(canReveal(intent))
        }
    }

    func testFullscreenStillNeedsTwoDeliberatePushes() {
        var intent = DockEdgeIntent()
        var fullscreen = AutoHideRevealGate()
        move(&intent)
        XCTAssertTrue(move(&intent, dy: 5, at: 1.01))
        XCTAssertEqual(fullscreen.update(targetKey: "A", requiresSecondPush: true, now: 1.01), .waitingForSecondPush)
        move(&intent, key: nil, at: 1.1)
        fullscreen.update(targetKey: nil, requiresSecondPush: false, now: 1.1)
        XCTAssertFalse(move(&intent, dy: 100, at: 1.2))
        XCTAssertTrue(move(&intent, dy: 5, at: 1.21))
        XCTAssertEqual(fullscreen.update(targetKey: "A", requiresSecondPush: true, now: 1.21), .ready)
    }

    func testClickOrScrollCannotPrimeFullscreenSecondPush() {
        var intent = DockEdgeIntent()
        var fullscreen = AutoHideRevealGate()
        move(&intent)
        move(&intent, dy: 5, at: 1.01)
        fullscreen.update(targetKey: "A", requiresSecondPush: true, now: 1.01)
        intent.reset()
        fullscreen.reset()
        move(&intent, at: 1.1)
        XCTAssertTrue(move(&intent, dy: 5, at: 1.11))
        XCTAssertEqual(fullscreen.update(targetKey: "A", requiresSecondPush: true, now: 1.11), .waitingForSecondPush)
    }
}
