import Foundation

enum DockDragReordering {
    static func items(_ original: [DockItem], moving item: DockItem, to point: CGPoint,
                      frames: [UUID: CGRect], position: DockPosition) -> [DockItem] {
        guard item.bundleIdentifier != "com.apple.finder" else { return original }
        var remaining = original.filter { $0.id != item.id }
        if remaining.contains(where: { $0.identityKey == item.identityKey }) { return original }
        let sectionIndices = remaining.indices.filter { remaining[$0].isApplication == item.isApplication && remaining[$0].bundleIdentifier != "com.apple.finder" }
        let next = sectionIndices.first { index in
            guard let frame = frames[remaining[index].id] else { return false }
            return position.isVertical ? point.y > frame.midY : point.x < frame.midX
        }
        let sectionEnd = item.isApplication ? (remaining.firstIndex { !$0.isApplication } ?? remaining.count) : remaining.count
        let index = next ?? sectionEnd
        var pinned = item
        pinned.isPinned = true
        pinned.runningProcessIdentifier = nil
        pinned.runningTileScope = nil
        remaining.insert(pinned, at: index)
        return remaining
    }
}
