import AppKit
import Foundation
import UniformTypeIdentifiers

struct FolderStackEntry: Identifiable, Equatable {
    var id: String { url.standardizedFileURL.path }
    var title: String
    var url: URL
    var isDirectory: Bool
    var kindDescription: String
    var dateAdded: Date?
    var dateModified: Date?
    var dateCreated: Date?
}

enum FolderStackService {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isHiddenKey,
        .localizedNameKey,
        .contentModificationDateKey,
        .creationDateKey,
        .addedToDirectoryDateKey,
        .contentTypeKey
    ]

    static func entries(for item: DockItem, limit: Int? = nil) -> [FolderStackEntry] {
        guard item.isFolder, let folderURL = item.url else {
            return []
        }

        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )
            let entries = urls.compactMap(entry(for:))
            return sorted(entries, by: item.folderSortMode, limit: limit)
        } catch {
            DockingLog.dock.error("Could not read folder stack \(folderURL.path): \(error.localizedDescription)")
            return []
        }
    }

    static func sorted(_ entries: [FolderStackEntry], by sortMode: DockFolderSortMode, limit: Int? = nil) -> [FolderStackEntry] {
        let sortedEntries = entries.sorted { lhs, rhs in
            switch sortMode {
            case .name:
                return localizedCompare(lhs.title, rhs.title)
            case .dateAdded:
                return compareDates(lhs.dateAdded, rhs.dateAdded, fallback: lhs.title, rhs.title)
            case .dateModified:
                return compareDates(lhs.dateModified, rhs.dateModified, fallback: lhs.title, rhs.title)
            case .dateCreated:
                return compareDates(lhs.dateCreated, rhs.dateCreated, fallback: lhs.title, rhs.title)
            case .kind:
                if lhs.kindDescription != rhs.kindDescription {
                    return localizedCompare(lhs.kindDescription, rhs.kindDescription)
                }
                return localizedCompare(lhs.title, rhs.title)
            }
        }

        if let limit {
            return Array(sortedEntries.prefix(limit))
        }
        return sortedEntries
    }

    private static func entry(for url: URL) -> FolderStackEntry? {
        let values = try? url.resourceValues(forKeys: resourceKeys)
        guard values?.isHidden != true else {
            return nil
        }

        let contentType = values?.contentType
        let kindDescription = contentType?.localizedDescription
            ?? (values?.isDirectory == true ? "Folder" : "File")

        return FolderStackEntry(
            title: values?.localizedName?.nilIfBlank ?? url.lastPathComponent,
            url: url.standardizedFileURL,
            isDirectory: values?.isDirectory == true,
            kindDescription: kindDescription,
            dateAdded: values?.addedToDirectoryDate,
            dateModified: values?.contentModificationDate,
            dateCreated: values?.creationDate
        )
    }

    private static func localizedCompare(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private static func compareDates(_ lhsDate: Date?, _ rhsDate: Date?, fallback lhsTitle: String, _ rhsTitle: String) -> Bool {
        switch (lhsDate, rhsDate) {
        case let (lhs?, rhs?) where lhs != rhs:
            // The Apple Dock presents date-based stacks with the newest items
            // first, which is the useful behavior for Downloads and Recents-like
            // folders. Ascending dates would bury the newest download at the end
            // and make Docking feel unlike the system Dock.
            return lhs > rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return localizedCompare(lhsTitle, rhsTitle)
        }
    }
}

enum FolderStackPresentation {
    static func resolvedViewMode(for item: DockItem, entryCount: Int) -> DockFolderViewMode {
        guard item.folderViewMode == .automatic else {
            return item.folderViewMode
        }

        // Apple's Automatic mode adapts to available space and item count. We
        // keep that intent without trying to clone Dock-private geometry: small
        // folders get the glanceable Fan, medium folders use Grid, and large
        // folders use List so long names remain readable.
        if entryCount <= 8 {
            return .fan
        }
        if entryCount <= 36 {
            return .grid
        }
        return .list
    }

    static func panelSize(for item: DockItem, entryCount: Int) -> CGSize {
        switch resolvedViewMode(for: item, entryCount: entryCount) {
        case .automatic:
            return CGSize(width: 380, height: 320)
        case .fan:
            let rowCount = min(max(entryCount, 1), 10)
            return CGSize(width: 300, height: CGFloat(72 + rowCount * 42))
        case .grid:
            return CGSize(width: 420, height: 360)
        case .list:
            return CGSize(width: 380, height: min(480, max(220, CGFloat(82 + min(entryCount, 12) * 32))))
        }
    }
}

enum FolderStackIconFactory {
    static func icon(for item: DockItem) -> NSImage? {
        guard item.isFolder, item.folderDisplayMode == .stack else {
            return nil
        }

        let entries = FolderStackService.entries(for: item, limit: 3)
        guard !entries.isEmpty else {
            return item.url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        }

        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        for (index, entry) in entries.reversed().enumerated() {
            let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
            let offset = CGFloat(index) * 12
            let rect = NSRect(x: 18 + offset, y: 14 + offset, width: 76, height: 76)
            let background = NSBezierPath(roundedRect: rect.insetBy(dx: -5, dy: -5), xRadius: 14, yRadius: 14)
            NSColor.windowBackgroundColor.withAlphaComponent(0.78).setFill()
            background.fill()
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }

        image.unlockFocus()
        return image
    }
}

enum SpecialFolderIconFactory {
    static func icon(for item: DockItem) -> NSImage? {
        guard item.isFolder,
              let url = item.url,
              let symbolName = symbolName(forFolderAt: url) else {
            return nil
        }

        return symbolIcon(symbolName: symbolName, accessibilityDescription: item.title)
    }

    static func symbolName(forFolderAt url: URL, downloadsDirectory: URL? = nil) -> String? {
        let standardDownloadsDirectory = downloadsDirectory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard let standardDownloadsDirectory else {
            return nil
        }

        if url.standardizedFileURL.path == standardDownloadsDirectory.standardizedFileURL.path {
            // Finder's sidebar represents Downloads with a symbolic down-arrow
            // mark, not with a generic blue folder. For a Dock replacement, the
            // semantic shortcut matters more than showing the first downloaded
            // file as a stack preview: users should recognize Downloads at a
            // glance even when the folder contents are noisy.
            return "arrow.down.circle"
        }

        return nil
    }

    private static func symbolIcon(symbolName: String, accessibilityDescription: String) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 92, weight: .semibold)) else {
            return nil
        }

        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let symbolRect = NSRect(x: 16, y: 16, width: 96, height: 96)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.set()

        // The icon is rendered into an NSImage because Docking's icon cache is
        // shared by the dock, Control Center, and stack panels. Keeping the
        // symbol here avoids adding separate SwiftUI icon branches that would
        // drift visually between those surfaces.
        tinted(symbol, color: .labelColor).draw(in: symbolRect)

        image.unlockFocus()
        return image
    }

    private static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let tintedImage = NSImage(size: image.size)
        tintedImage.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        rect.fill(using: .sourceAtop)
        tintedImage.unlockFocus()
        return tintedImage
    }
}
