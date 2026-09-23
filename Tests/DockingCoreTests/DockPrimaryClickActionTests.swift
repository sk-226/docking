import AppKit
import XCTest
@testable import DockingCore

final class DockPrimaryClickActionTests: XCTestCase {
    func testCommandOptionLaunchTakesPriorityOverFinderReveal() {
        XCTAssertEqual(DockPrimaryClickAction.resolve(isApplication: true, modifiers: [.command, .option]), .openHidingOthers)
        XCTAssertEqual(DockPrimaryClickAction.resolve(isApplication: true, modifiers: [.command]), .showInFinder)
        XCTAssertEqual(DockPrimaryClickAction.resolve(isApplication: true, modifiers: [.option]), .toggleApplication)
        XCTAssertEqual(DockPrimaryClickAction.resolve(isApplication: true, modifiers: []), .open)
    }

    func testFoldersDoNotAcquireApplicationHideCommands() {
        XCTAssertEqual(DockPrimaryClickAction.resolve(isApplication: false, modifiers: [.command, .option]), .showInFinder)
        XCTAssertEqual(DockPrimaryClickAction.resolve(isApplication: false, modifiers: [.option]), .open)
    }
}
