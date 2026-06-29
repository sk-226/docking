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
    static let downloadsInitialVisibleCount = 12

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
            // This reads only the immediate children and requested metadata, not
            // file contents and not descendants inside downloaded folders. For
            // Downloads, exact "recent first" order requires metadata for the
            // direct items; loading icons and row views remains lazy in the
            // panel so opening the stack does not decode everything at once.
            let urls = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )
            let entries = urls.compactMap(entry(for:))
            if isDownloadsFolder(folderURL) {
                return recentDownloads(entries, limit: limit)
            }
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

    static func isDownloadsFolder(_ url: URL, downloadsDirectory: URL? = nil) -> Bool {
        let standardDownloadsDirectory = downloadsDirectory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)

        return isSameFolder(url, standardDownloadsDirectory)
    }

    static func recentDownloads(_ entries: [FolderStackEntry], limit: Int? = nil) -> [FolderStackEntry] {
        // Downloads is the one folder where "recent" is more important than a
        // generic folder sort. The Dock is usually used to recover the file that
        // just arrived, so showing an alphabetic list here is technically simple
        // but product-wrong. We keep this special case local to Downloads rather
        // than changing every folder stack's sort semantics.
        let sortedEntries = entries.sorted { lhs, rhs in
            switch (recentDate(for: lhs), recentDate(for: rhs)) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs > rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
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

    private static func recentDate(for entry: FolderStackEntry) -> Date? {
        entry.dateAdded ?? entry.dateModified ?? entry.dateCreated
    }

    private static func isSameFolder(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path == rhs.standardizedFileURL.resolvingSymlinksInPath().path
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

        if let url = item.url, FolderStackService.isDownloadsFolder(url) {
            return .grid
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
        guard item.isFolder else {
            return nil
        }

        let isDownloads = item.url.map { FolderStackService.isDownloadsFolder($0) } ?? false
        guard !isDownloads else {
            return nil
        }

        guard item.folderDisplayMode == .stack else {
            return nil
        }

        let entries = FolderStackService.entries(for: item, limit: 3)
        guard !entries.isEmpty else {
            return item.url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        }

        return DockIconImageRenderer.render { _ in
            for (index, entry) in entries.reversed().enumerated() {
                let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
                let offset = CGFloat(index) * 24
                let rect = NSRect(x: 36 + offset, y: 28 + offset, width: 152, height: 152)
                let background = NSBezierPath(roundedRect: rect.insetBy(dx: -10, dy: -10), xRadius: 28, yRadius: 28)
                NSColor.windowBackgroundColor.withAlphaComponent(0.78).setFill()
                background.fill()
                icon.draw(
                    in: rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
            }
        }
    }
}

enum SpecialFolderIconFactory {
    private static let downloadsSymbolName = "arrow.down.circle.fill"

    static func icon(for item: DockItem) -> NSImage? {
        guard item.isFolder,
              let url = item.url,
              let symbolName = symbolName(forFolderAt: url) else {
            return nil
        }

        if symbolName == downloadsSymbolName {
            return downloadsIcon(accessibilityDescription: item.title)
        }

        return symbolIcon(symbolName: symbolName, accessibilityDescription: item.title)
    }

    static func symbolName(forFolderAt url: URL, downloadsDirectory: URL? = nil) -> String? {
        let standardDownloadsDirectory = downloadsDirectory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard let standardDownloadsDirectory else {
            return nil
        }

        if FolderStackService.isDownloadsFolder(url, downloadsDirectory: standardDownloadsDirectory) {
            // Finder's sidebar represents Downloads with a symbolic down-arrow
            // mark, not with a generic blue folder. For a Dock replacement, the
            // semantic shortcut matters more than showing the first downloaded
            // file as a stack preview: users should recognize Downloads at a
            // glance even when the folder contents are noisy.
            return downloadsSymbolName
        }

        return nil
    }

    private static func downloadsIcon(accessibilityDescription _: String) -> NSImage {
        DockIconImageRenderer.render { _ in
            // SF Symbols are normally the right answer, but the circular
            // Downloads glyph has less visual area than square app icons. Scaling
            // that circle in SwiftUI made the tile drift off-center. Drawing a
            // full-size rounded-square asset keeps the Finder download metaphor
            // while giving SwiftUI a normal centered image like every app icon.
            let backgroundRect = NSRect(x: 4, y: 4, width: 248, height: 248)
            let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 54, yRadius: 54)
            NSColor.systemBlue.setFill()
            background.fill()

            let arrow = NSBezierPath()
            arrow.lineWidth = 32
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.move(to: NSPoint(x: 128, y: 184))
            arrow.line(to: NSPoint(x: 128, y: 74))
            arrow.move(to: NSPoint(x: 76, y: 126))
            arrow.line(to: NSPoint(x: 128, y: 74))
            arrow.line(to: NSPoint(x: 180, y: 126))
            NSColor.white.setStroke()
            arrow.stroke()
        }
    }

    private static func symbolIcon(symbolName: String, accessibilityDescription: String) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 224, weight: .medium)) else {
            return nil
        }

        return DockIconImageRenderer.render { _ in
            // This generic path is intentionally plain. Folder-specific artwork
            // such as Downloads gets a dedicated renderer above when a symbol's
            // optical bounds need tuning; the fallback should not add shadows or
            // visual treatments that would make future special folders fight the
            // system glyph shape.
            tinted(symbol, color: .labelColor).draw(
                in: NSRect(x: 10, y: 10, width: 236, height: 236),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
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
