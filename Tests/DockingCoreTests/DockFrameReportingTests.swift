import AppKit
import XCTest
@testable import DockingCore

final class DockFrameReportingTests: XCTestCase {
    @MainActor
    func testHiddenWindowMoveRefreshesTheSourceClickRegion() async throws {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 300, height: 60),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.close() }
        let firstReport = expectation(description: "Initial screen frame")
        var reported = CGRect.zero
        let view = DockFrameReportingView()
        view.onFrameChange = { frame in
            reported = frame
            firstReport.fulfill()
        }
        view.frame = CGRect(x: 20, y: 3, width: 36, height: 42)
        try XCTUnwrap(window.contentView).addSubview(view)
        await fulfillment(of: [firstReport], timeout: 1)
        let movedReport = expectation(description: "Moved window screen frame")
        view.onFrameChange = { frame in
            reported = frame
            movedReport.fulfill()
        }
        window.setFrameOrigin(CGPoint(x: 100, y: 158))
        await fulfillment(of: [movedReport], timeout: 1)
        let actual = window.convertToScreen(view.convert(view.bounds, to: nil))
        XCTAssertEqual(reported, actual)
        let stackFrame = CGRect(x: actual.midX - 100, y: actual.maxY + 30, width: 200, height: 200)
        XCTAssertFalse(FolderStackPanelController.shouldDismissPointerEvent(
            pointerLocation: CGPoint(x: actual.midX, y: actual.midY), panelFrame: stackFrame, anchorFrame: reported))
    }
}
