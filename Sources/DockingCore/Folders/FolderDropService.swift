import AppKit
import Foundation

enum FolderDropOperation: Equatable {
    case copy
    case move
}

enum FolderDropError: LocalizedError, Equatable {
    case sourceMissing(URL)
    case targetMissing(URL)
    case targetIsNotFolder(URL)
    case destinationAlreadyExists(URL)
    case droppingFolderIntoItself(URL)

    var errorDescription: String? {
        switch self {
        case let .sourceMissing(url):
            return "The original item no longer exists: \(url.path)"
        case let .targetMissing(url):
            return "The destination folder no longer exists: \(url.path)"
        case let .targetIsNotFolder(url):
            return "The destination is not a folder: \(url.path)"
        case let .destinationAlreadyExists(url):
            return "An item with the same name already exists in the folder: \(url.lastPathComponent)"
        case let .droppingFolderIntoItself(url):
            return "A folder cannot be moved or copied into itself: \(url.path)"
        }
    }
}

enum FolderDropService {
    static func performDrop(
        sourceURL: URL,
        into targetFolderURL: URL,
        modifierFlags: NSEvent.ModifierFlags = NSEvent.modifierFlags,
        fileManager: FileManager = .default
    ) throws -> URL {
        let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        let targetFolder = targetFolderURL.standardizedFileURL.resolvingSymlinksInPath()

        try validate(source: source, targetFolder: targetFolder, fileManager: fileManager)

        let destination = targetFolder.appendingPathComponent(source.lastPathComponent)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FolderDropError.destinationAlreadyExists(destination)
        }

        switch operation(sourceURL: source, targetFolderURL: targetFolder, modifierFlags: modifierFlags) {
        case .copy:
            try fileManager.copyItem(at: source, to: destination)
        case .move:
            try fileManager.moveItem(at: source, to: destination)
        }

        return destination
    }

    static func operation(
        sourceURL: URL,
        targetFolderURL: URL,
        modifierFlags: NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) -> FolderDropOperation {
        // Finder's ordinary rule is the closest public behavior users expect:
        // Option copies, otherwise same-volume drags move and cross-volume drags
        // copy. We do not invent a Docking-specific prompt here because a Dock
        // folder should feel like a folder proxy, not a separate importer UI.
        if modifierFlags.contains(.option) {
            return .copy
        }

        return sharesVolume(sourceURL, targetFolderURL) ? .move : .copy
    }

    private static func validate(source: URL, targetFolder: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            throw FolderDropError.sourceMissing(source)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: targetFolder.path, isDirectory: &isDirectory) else {
            throw FolderDropError.targetMissing(targetFolder)
        }
        guard isDirectory.boolValue else {
            throw FolderDropError.targetIsNotFolder(targetFolder)
        }

        var sourceIsDirectory: ObjCBool = false
        _ = fileManager.fileExists(atPath: source.path, isDirectory: &sourceIsDirectory)
        if sourceIsDirectory.boolValue, isSameOrDescendant(targetFolder, of: source) {
            // Finder refuses recursive folder moves/copies. Catching it before
            // FileManager runs gives Docking a clear user-facing error instead
            // of a low-level POSIX failure string.
            throw FolderDropError.droppingFolderIntoItself(source)
        }
    }

    private static func sharesVolume(_ lhs: URL, _ rhs: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeURLKey]
        let lhsVolume = try? lhs.resourceValues(forKeys: keys).volume
        let rhsVolume = try? rhs.resourceValues(forKeys: keys).volume
        guard let lhsVolume, let rhsVolume else {
            // Unknown volume identity should bias toward copying. Moving is
            // destructive; if macOS cannot prove same-volume semantics for us,
            // preserving the source is the safer Finder-like fallback.
            return false
        }
        return lhsVolume.standardizedFileURL == rhsVolume.standardizedFileURL
    }

    private static func isSameOrDescendant(_ child: URL, of parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.resolvingSymlinksInPath().path
        let parentPath = parent.standardizedFileURL.resolvingSymlinksInPath().path
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }
}
