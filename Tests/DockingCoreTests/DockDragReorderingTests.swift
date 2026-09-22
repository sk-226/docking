import XCTest
@testable import DockingCore

final class DockDragReorderingTests: XCTestCase {
    func testDraggingAcrossCentersReachesBothEndsWithoutLosingItems() {
        let items = (0..<4).map { DockItem(title: "Item \($0)", bundleIdentifier: "test.\($0)", url: nil, iconCacheKey: "\($0)") }
        let frames = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, CGRect(x: 100 + $0.offset * 50, y: 10, width: 40, height: 40)) })
        let last = DockDragReordering.items(items, moving: items[0], to: CGPoint(x: 290, y: 30), frames: frames, position: .bottomCenter)
        XCTAssertEqual(last.map(\.id), [items[1].id, items[2].id, items[3].id, items[0].id])
        let first = DockDragReordering.items(items, moving: items[3], to: CGPoint(x: 100, y: 30), frames: frames, position: .bottomCenter)
        XCTAssertEqual(first.map(\.id), [items[3].id, items[0].id, items[1].id, items[2].id])
    }

    func testVerticalCoordinatesAndTransientPinning() {
        let item = DockItem(title: "Pinned", bundleIdentifier: "test.pinned", url: nil, iconCacheKey: "pinned")
        let live = DockItem(title: "Live", bundleIdentifier: "test.live", url: nil, iconCacheKey: "live", runningProcessIdentifier: 123, runningTileScope: .process, isPinned: false)
        let result = DockDragReordering.items([item], moving: live, to: CGPoint(x: 20, y: 100), frames: [item.id: CGRect(x: 10, y: 50, width: 40, height: 40)], position: .right)
        XCTAssertEqual(result.map(\.id), [live.id, item.id])
        XCTAssertTrue(result[0].isPinned)
        XCTAssertNil(result[0].runningProcessIdentifier)
        XCTAssertNil(result[0].runningTileScope)
    }

    func testFinderCannotBeMovedAndExistingAppCannotBeDuplicated() {
        let finder = DockItem(title: "Finder", bundleIdentifier: "com.apple.finder", url: nil, iconCacheKey: "finder")
        let twin = DockItem(title: "Finder", bundleIdentifier: "com.apple.finder", url: nil, iconCacheKey: "finder")
        XCTAssertEqual(DockDragReordering.items([finder], moving: twin, to: .zero, frames: [:], position: .left), [finder])
        let app = DockItem(title: "App", bundleIdentifier: "test.app", url: nil, iconCacheKey: "app")
        var second = app
        second.id = UUID()
        second.isPinned = false
        XCTAssertEqual(DockDragReordering.items([finder, app], moving: second, to: .zero, frames: [:], position: .bottomCenter), [finder, app])
    }

    func testCrowdedReorderingKeepsAllItemsAndSectionBoundaries() {
        let apps = (0..<32).map { DockItem(title: "App \($0)", bundleIdentifier: "test.\($0)", url: nil, iconCacheKey: "\($0)") }
        let folders = (0..<3).map { DockItem(kind: .folder, title: "Folder \($0)", bundleIdentifier: nil, url: URL(fileURLWithPath: "/tmp/folder-\($0)"), iconCacheKey: "folder-\($0)") }
        let original = [DockItemOrdering.finder] + apps + folders
        for position in DockPosition.allCases {
            let frames = Dictionary(uniqueKeysWithValues: original.enumerated().map {
                ($0.element.id, CGRect(x: 40 + Double($0.offset) * 22, y: 850 - Double($0.offset) * 22, width: 20, height: 20))
            })
            for source in [apps[0], apps[15], apps[31]] {
                for target in [original[0], apps[16], folders[2]] {
                    let frame = frames[target.id]!
                    let result = DockDragReordering.items(original, moving: source, to: CGPoint(x: frame.midX, y: frame.midY), frames: frames, position: position)
                    XCTAssertEqual(result.count, original.count)
                    XCTAssertEqual(Set(result.map(\.id)), Set(original.map(\.id)))
                    XCTAssertEqual(result.first?.bundleIdentifier, "com.apple.finder")
                    XCTAssertEqual(Array(result.suffix(3)), folders)
                }
            }
            let folderAtFront = DockDragReordering.items(original, moving: folders[2], to: CGPoint(x: -100, y: 1000), frames: frames, position: position)
            XCTAssertEqual(Array(folderAtFront.prefix(33)), [DockItemOrdering.finder] + apps)
            XCTAssertEqual(Array(folderAtFront.suffix(3)), [folders[2], folders[0], folders[1]])
        }
    }

}
