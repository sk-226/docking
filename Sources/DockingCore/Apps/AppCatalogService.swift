import AppKit
import Foundation
import UniformTypeIdentifiers

final class AppCatalogService {
    @MainActor
    func chooseDockItem() -> DockItem? {
        let panel = NSOpenPanel()
        panel.title = "Add to Docking"
        panel.prompt = "Add"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle, .folder]

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return Self.dockItemIfSupported(for: url)
    }

    static func dockItemIfSupported(for url: URL) -> DockItem? {
        let standardizedURL = url.standardizedFileURL

        if isApplicationBundle(standardizedURL) {
            return applicationDockItem(for: standardizedURL)
        }

        if isFolder(standardizedURL) {
            return folderDockItem(for: standardizedURL)
        }

        return nil
    }

    static func applicationDockItem(for url: URL) -> DockItem {
        let standardizedURL = url.standardizedFileURL
        let bundle = Bundle(url: standardizedURL)
        let bundleIdentifier = bundle?.bundleIdentifier
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let title = displayName ?? bundleName ?? standardizedURL.deletingPathExtension().lastPathComponent

        return DockItem(
            kind: .application,
            title: title,
            bundleIdentifier: bundleIdentifier,
            url: standardizedURL,
            iconCacheKey: bundleIdentifier ?? "application:\(standardizedURL.path)"
        )
    }

    static func folderDockItem(
        for url: URL,
        displayMode: DockFolderDisplayMode = .folder,
        viewMode: DockFolderViewMode = .automatic,
        sortMode: DockFolderSortMode = .name
    ) -> DockItem {
        let standardizedURL = url.standardizedFileURL

        return DockItem(
            kind: .folder,
            title: localizedDisplayName(for: standardizedURL),
            bundleIdentifier: nil,
            url: standardizedURL,
            iconCacheKey: "folder:\(standardizedURL.path)",
            folderDisplayMode: displayMode,
            folderViewMode: viewMode,
            folderSortMode: sortMode
        )
    }

    private static func isApplicationBundle(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        guard values?.isDirectory == true else {
            return false
        }

        // App bundles are directories on disk, but they must keep app-specific
        // launch and process semantics. Checking this before the folder branch
        // prevents Quit/Force Quit from disappearing for apps dragged from
        // Finder, while still allowing ordinary directories to become stacks.
        return values?.contentType?.conforms(to: .applicationBundle) == true
    }

    private static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        guard values?.isDirectory == true else {
            return false
        }

        // Packages that conform to app bundle were handled above. Other
        // directories belong in Docking as folder stacks because the Apple Dock
        // stores them in persistent-others, not persistent-apps.
        return values?.contentType?.conforms(to: .applicationBundle) != true
    }

    static func localizedDisplayName(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.localizedNameKey])
        return values?.localizedName?.nilIfBlank ?? url.lastPathComponent
    }
}
