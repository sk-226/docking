import Foundation

enum DockItemOrdering {
    static let finder = DockItem(
        id: UUID(uuidString: "B2BD6E9F-D0BC-467C-91CC-71A420AA43FE")!,
        title: "Finder", bundleIdentifier: "com.apple.finder",
        url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
        iconCacheKey: "com.apple.finder"
    )

    static func normalized(_ items: [DockItem]) -> [DockItem] {
        let fixedFinder = items.first { $0.bundleIdentifier == "com.apple.finder" } ?? finder
        let movable = items.filter { $0.bundleIdentifier != "com.apple.finder" }
        return [fixedFinder] + movable.filter(\.isApplication) + movable.filter { !$0.isApplication }
    }

    static func visibleItems(pinned: [DockItem], running: [DockItem], visibility: UnpinnedRunningAppVisibility) -> [DockItem] {
        let ordered = normalized(pinned)
        let assigned = DockRunningItemResolver.assignedPinnedItems(pinnedItems: ordered, runningItems: running)
        let unpinned = DockRunningItemResolver.unpinnedRunningItems(pinnedItems: ordered, runningItems: running, visibility: visibility)
        return assigned.filter(\.isApplication) + unpinned + assigned.filter { !$0.isApplication }
    }

    static func documentStart(in items: [DockItem]) -> Int? {
        items.firstIndex { !$0.isApplication }
    }
}
