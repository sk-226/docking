import AppKit
import XCTest
@testable import DockingCore

final class DockEdgeInputTests: XCTestCase {
    @MainActor
    func testEdgePanelsNeverCaptureInput() {
        _ = NSApplication.shared
        let panel = AutoHideController.makeEdgePanel()
        defer { panel.close() }
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.contentView?.trackingAreas.isEmpty == true)
    }

    @MainActor
    func testBothMonitorsObserveInteractionsThatCancelReveal() {
        let mask = AutoHideController.observedEvents
        for event: NSEvent.EventTypeMask in [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ] {
            XCTAssertTrue(mask.contains(event))
        }
        XCTAssertFalse(mask.contains(.keyDown))
    }
}
