import XCTest
@testable import DockingCore

final class DockDragRemovalPolicyTests: XCTestCase {
    func testNativeGracePeriodAndInwardBoundary() {
        let frame = CGRect(x: 100, y: 10, width: 600, height: 48)
        for (y, time, expected) in [(200.0, 0.499, false), (106, 0.5, false), (107, 0.5, true)] {
            XCTAssertEqual(DockDragRemovalPolicy.canRemove(at: CGPoint(x: 300, y: y), from: frame,
                                                           position: .bottomCenter, elapsed: time,
                                                           isFixed: false, menuBarFrame: nil), expected)
        }
    }

    func testFixedTilesAndMenuBarNeverRemove() {
        let frame = CGRect(x: 100, y: 10, width: 600, height: 48)
        let menu = CGRect(x: 0, y: 878, width: 1400, height: 22)
        XCTAssertFalse(DockDragRemovalPolicy.canRemove(at: CGPoint(x: 200, y: 400), from: frame,
                                                       position: .bottomCenter, elapsed: 1, isFixed: true, menuBarFrame: menu))
        XCTAssertFalse(DockDragRemovalPolicy.canRemove(at: CGPoint(x: 200, y: 890), from: frame,
                                                       position: .bottomCenter, elapsed: 1, isFixed: false, menuBarFrame: menu))
    }

    func testSideEdgesUseTheSameInwardDistance() {
        let left = CGRect(x: -1000, y: 100, width: 48, height: 500)
        let right = CGRect(x: -48, y: 100, width: 48, height: 500)
        XCTAssertTrue(DockDragRemovalPolicy.canRemove(at: CGPoint(x: -903, y: 350), from: left,
                                                      position: .left, elapsed: 1, isFixed: false, menuBarFrame: nil))
        XCTAssertTrue(DockDragRemovalPolicy.canRemove(at: CGPoint(x: -97, y: 350), from: right,
                                                      position: .right, elapsed: 1, isFixed: false, menuBarFrame: nil))
        XCTAssertFalse(DockDragRemovalPolicy.canRemove(at: CGPoint(x: -97, y: 700), from: right,
                                                       position: .right, elapsed: 0.1, isFixed: false, menuBarFrame: nil))
    }
}
