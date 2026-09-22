import AppKit
import XCTest
@testable import DockingCore

final class DockWindowEventRegionTests: XCTestCase {
    func testScreenCoordinatesBecomeWindowLocalTopLeftCoordinates() {
        let window = CGRect(x: -400, y: 30, width: 800, height: 160)
        let content = CGRect(x: -250, y: 30, width: 500, height: 80)
        XCTAssertEqual(DockWindowEventRegion.region(contentFrame: content, windowFrame: window),
                       CGRect(x: 150, y: 80, width: 500, height: 80))
        let movedWindow = window.offsetBy(dx: 1000, dy: -55)
        let movedContent = content.offsetBy(dx: 1000, dy: -55)
        XCTAssertEqual(DockWindowEventRegion.region(contentFrame: movedContent, windowFrame: movedWindow),
                       DockWindowEventRegion.region(contentFrame: content, windowFrame: window))
    }

    func testSideDockRegionClipsOverflowAndExcludesTheTransparentCanvas() {
        let window = CGRect(x: 100, y: 50, width: 160, height: 600)
        let content = CGRect(x: 180, y: 10, width: 80, height: 500)
        XCTAssertEqual(DockWindowEventRegion.region(contentFrame: content, windowFrame: window),
                       CGRect(x: 80, y: 140, width: 80, height: 460))
        XCTAssertEqual(DockWindowEventRegion.region(contentFrame: CGRect(x: 300, y: 20, width: 5, height: 5), windowFrame: window), .zero)
    }
    @MainActor
    func testPrivateAPIInstallsAnEventRegionOnAnOwnedPanel() throws {
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 200, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { panel.close() }
        let region = try XCTUnwrap(DockWindowEventRegion())
        XCTAssertTrue(region.update(window: panel, contentFrame: CGRect(x: 110, y: 110, width: 50, height: 40)))
    }

}
