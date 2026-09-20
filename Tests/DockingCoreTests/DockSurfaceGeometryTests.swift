import Foundation
import XCTest
@testable import DockingCore

final class DockSurfaceGeometryTests: XCTestCase {
    func testBottomGlassStaysCompactDuringMagnification() {
        for position in [DockPosition.bottomCenter, .bottomLeft, .bottomRight] {
            let frame = DockSurfaceGeometry.frame(
                in: CGRect(x: 0, y: 0, width: 500, height: 140),
                size: CGSize(width: 500, height: 48), position: position
            )
            XCTAssertEqual(frame, CGRect(x: 0, y: 92, width: 500, height: 48))
        }
    }

    func testSideGlassStaysOnItsRestingEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 140, height: 500)
        let size = CGSize(width: 48, height: 500)
        XCTAssertEqual(DockSurfaceGeometry.frame(in: bounds, size: size, position: .left),
                       CGRect(x: 0, y: 0, width: 48, height: 500))
        XCTAssertEqual(DockSurfaceGeometry.frame(in: bounds, size: size, position: .right),
                       CGRect(x: 92, y: 0, width: 48, height: 500))
    }

    func testRestingGlassMatchesContentForEveryEdge() {
        for position in DockPosition.allCases {
            let bounds = position.isVertical
                ? CGRect(x: 0, y: 0, width: 48, height: 500)
                : CGRect(x: 0, y: 0, width: 500, height: 48)
            XCTAssertEqual(DockSurfaceGeometry.frame(in: bounds, size: bounds.size, position: position), bounds)
        }
    }

    func testShapeHonorsTranslatedBoundsAndClampsToContent() {
        let bounds = CGRect(x: 17, y: 29, width: 500, height: 140)
        XCTAssertEqual(DockSurfaceGeometry.frame(in: bounds, size: CGSize(width: 300, height: 48), position: .bottomCenter),
                       CGRect(x: 117, y: 121, width: 300, height: 48))
        for position in DockPosition.allCases {
            XCTAssertEqual(DockSurfaceGeometry.frame(in: bounds, size: CGSize(width: 900, height: 900), position: position), bounds)
        }
    }
}
