import AppKit
import Foundation

final class AppListStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = (try? AppSupportDirectory.url()) ?? FileManager.default.temporaryDirectory
            self.fileURL = directory.appendingPathComponent("DockItems.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> [DockItem] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return Self.defaultItems()
        }

        do {
            let items = try decoder.decode([DockItem].self, from: data)
            return items.isEmpty ? Self.defaultItems() : items
        } catch {
            // The app list is user-editable state, but losing the whole dock over
            // a bad JSON file would be a poor failure mode. We keep the fallback
            // small and predictable so the user can still open Control Center.
            DockingLog.app.error("Failed to decode app list: \(error.localizedDescription)")
            return Self.defaultItems()
        }
    }

    func save(_ items: [DockItem]) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(items).write(to: fileURL, options: .atomic)
        } catch {
            DockingLog.app.error("Failed to save app list: \(error.localizedDescription)")
        }
    }

    static func defaultItems() -> [DockItem] {
        [
            item(title: "Finder", bundleIdentifier: "com.apple.finder"),
            item(title: "Safari", bundleIdentifier: "com.apple.Safari"),
            item(title: "Calendar", bundleIdentifier: "com.apple.iCal"),
            item(title: "Notes", bundleIdentifier: "com.apple.Notes"),
            item(title: "Terminal", bundleIdentifier: "com.apple.Terminal")
        ]
    }

    private static func item(title: String, bundleIdentifier: String) -> DockItem {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        return DockItem(
            kind: .application,
            title: title,
            bundleIdentifier: bundleIdentifier,
            url: url,
            iconCacheKey: bundleIdentifier
        )
    }
}
