import Foundation

enum DockDropTarget: Equatable {
    case openApplication(UUID)
    case folder(UUID)
    case insert(before: UUID?)

    static func resolve(at point: CGPoint, insertingApplication: Bool, items: [DockItem],
                        frames: [UUID: CGRect], position: DockPosition) -> DockDropTarget {
        for item in items {
            guard let frame = frames[item.id] else { continue }
            let center = position.isVertical
                ? frame.insetBy(dx: 0, dy: frame.height * 0.25)
                : frame.insetBy(dx: frame.width * 0.25, dy: 0)
            if center.contains(point) {
                if item.isApplication { return .openApplication(item.id) }
                if item.isFolder { return .folder(item.id) }
            }
        }
        let section = items.filter { $0.isPinned && $0.isApplication == insertingApplication && $0.bundleIdentifier != "com.apple.finder" }
        let next = section.first { item in
            guard let frame = frames[item.id] else { return false }
            return position.isVertical ? point.y > frame.midY : point.x < frame.midX
        }
        return .insert(before: next?.id ?? (insertingApplication ? items.first(where: { !$0.isApplication })?.id : nil))
    }
}

enum DockDragGeometry {
    static func frames(items: [DockItem], metrics: DockLayoutMetrics, contentFrame: CGRect,
                       settings: DockingSettings) -> [UUID: CGRect] {
        let vertical = settings.dockPosition.isVertical
        let sections = Set([DockItemOrdering.documentStart(in: items), items.firstIndex { !$0.isPinned }].compactMap { $0 })
        var cursor = metrics.padding
        var frames: [UUID: CGRect] = [:]
        for (index, item) in items.enumerated() {
            guard metrics.iconSizes.indices.contains(index) else { break }
            if sections.contains(index) { cursor += 1 + settings.spacing }
            cursor += metrics.iconLeadingInsets[index]
            let size = metrics.iconSizes[index]
            let scale = metrics.scale
            let frame: CGRect
            if vertical {
                let width = (size + DockLayout.indicatorSpace) * scale
                frame = CGRect(x: settings.dockPosition == .left ? contentFrame.minX + 3 * scale : contentFrame.maxX - 3 * scale - width,
                               y: contentFrame.maxY - (cursor + size) * scale, width: width, height: size * scale)
            } else {
                frame = CGRect(x: contentFrame.minX + cursor * scale, y: contentFrame.minY + 3 * scale,
                               width: size * scale, height: (size + DockLayout.indicatorSpace) * scale)
            }
            frames[item.id] = frame
            cursor += size + settings.spacing
        }
        return frames
    }
}
