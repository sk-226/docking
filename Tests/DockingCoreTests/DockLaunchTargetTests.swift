import XCTest
@testable import DockingCore

final class DockLaunchTargetTests: XCTestCase {
    func testSecondProcessBouncesItsOwnTile() {
        let pinned = DockItem(title: "App", bundleIdentifier: "test.app", url: nil, iconCacheKey: "app", runningProcessIdentifier: 10)
        var second = pinned
        second.id = UUID()
        second.runningProcessIdentifier = 20
        second.isPinned = false
        let application = RunningApplicationSnapshot(processIdentifier: 20, activationPolicy: .regular, bundleIdentifier: "test.app", bundleURL: nil)
        XCTAssertEqual(DockLaunchTarget.itemID(for: application, candidates: [pinned, second]), second.id)
        XCTAssertNil(DockLaunchTarget.itemID(for: application, candidates: [pinned]))
    }

    func testUnlaunchedPinnedItemCanReceiveTheFirstLaunch() {
        let pinned = DockItem(title: "App", bundleIdentifier: "test.app", url: nil, iconCacheKey: "app")
        let application = RunningApplicationSnapshot(processIdentifier: 20, activationPolicy: .regular, bundleIdentifier: "test.app", bundleURL: nil)
        XCTAssertEqual(DockLaunchTarget.itemID(for: application, candidates: [pinned]), pinned.id)
    }
}
