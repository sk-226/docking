import AppKit
import Foundation

@MainActor
final class AppIconCache {
    private var icons: [String: NSImage] = [:]

    func icon(for item: DockItem) -> NSImage {
        let cacheKey = item.renderedIconCacheKey
        if let cached = icons[cacheKey] {
            return cached
        }

        let icon: NSImage
        if let specialFolderIcon = SpecialFolderIconFactory.icon(for: item) {
            icon = specialFolderIcon
        } else if item.isFolder, item.folderDisplayMode == .stack, let stackIcon = FolderStackIconFactory.icon(for: item) {
            icon = stackIcon
        } else if let url = item.url {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else if let bundleIdentifier = item.bundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: item.title) ?? NSImage()
        }

        // Icon decoding and stack-preview composition are expensive enough that
        // SwiftUI body recomputation should not redo them. The cache key is
        // based on item identity plus the folder choices that affect rendering,
        // so simple reordering does not invalidate images.
        icons[cacheKey] = icon
        return icon
    }

    func clear() {
        icons.removeAll()
    }
}
