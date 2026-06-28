import AppKit
import Foundation
import UniformTypeIdentifiers

final class AppCatalogService {
    @MainActor
    func chooseApplication() -> DockItem? {
        let panel = NSOpenPanel()
        panel.title = "Add Application"
        panel.prompt = "Add"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return Self.dockItemIfApplication(for: url)
    }

    static func dockItemIfApplication(for url: URL) -> DockItem? {
        let standardizedURL = url.standardizedFileURL
        guard isApplicationBundle(standardizedURL) else {
            return nil
        }

        return dockItem(for: standardizedURL)
    }

    static func dockItem(for url: URL) -> DockItem {
        let bundle = Bundle(url: url)
        let bundleIdentifier = bundle?.bundleIdentifier
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let title = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent

        return DockItem(
            title: title,
            bundleIdentifier: bundleIdentifier,
            appURL: url,
            iconCacheKey: bundleIdentifier ?? url.path
        )
    }

    private static func isApplicationBundle(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        guard values?.isDirectory == true else {
            return false
        }

        // The dock should only accept real application bundles from drag and
        // drop. Treating arbitrary directories as apps would create launcher
        // rows that cannot open predictably and would make later icon caching
        // harder to reason about.
        return values?.contentType?.conforms(to: .applicationBundle) == true
    }
}
