import AppKit
import Foundation

@MainActor
final class AppIconCache {
    private var icons: [String: NSImage] = [:]

    func icon(for item: DockItem) -> NSImage {
        if let cached = icons[item.iconCacheKey] {
            return cached
        }

        let icon: NSImage
        if let url = item.appURL {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else if let bundleIdentifier = item.bundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: item.title) ?? NSImage()
        }

        // App icon decoding is not something we want SwiftUI to redo on every
        // body recomputation. The cache is intentionally keyed by bundle/path so
        // reordering items does not invalidate images.
        icons[item.iconCacheKey] = icon
        return icon
    }

    func clear() {
        icons.removeAll()
    }
}
