import AppKit
import Foundation

enum AppleDockPreferences {
    static func visibilityMode(from dockDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock")) -> DockVisibilityMode {
        guard let autohide = dockAutohideValue(from: dockDefaults) else {
            // If the Dock domain cannot be read, prefer the mode the user asked
            // for in this pre-release build: Docking should behave like an auto-hide
            // dock instead of permanently covering the workspace. This is a
            // product default, not an old-version migration path.
            return .autoHide
        }

        return autohide ? .autoHide : .alwaysVisible
    }

    static func visibilityStatusText(from dockDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock")) -> String {
        guard let autohide = dockAutohideValue(from: dockDefaults) else {
            return "Apple Dock visibility could not be read. Docking will use auto-hide."
        }

        return autohide
            ? "Apple Dock is set to auto-hide."
            : "Apple Dock is set to always show."
    }

    static func mirrorOriginalDock(
        into settings: inout DockingSettings,
        savedValues: [String: DockPreferenceValue]?,
        dockDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock")
    ) -> Bool {
        var didApply = false

        if let autohide = boolValue(forKey: "autohide", savedValues: savedValues, dockDefaults: dockDefaults) {
            settings.dockVisibility = autohide ? .autoHide : .alwaysVisible
            didApply = true
        }

        if let orientation = stringValue(forKey: "orientation", savedValues: savedValues, dockDefaults: dockDefaults),
           let position = dockPosition(forAppleDockOrientation: orientation) {
            settings.dockPosition = position
            didApply = true
        }

        if let tileSize = doubleValue(forKey: "tilesize", savedValues: savedValues, dockDefaults: dockDefaults) {
            let iconSize = clamped(tileSize, to: DockingSettingLimits.iconSize)
            settings.iconSize = iconSize
            didApply = true
        }

        if let magnification = boolValue(forKey: "magnification", savedValues: savedValues, dockDefaults: dockDefaults) {
            settings.magnificationEnabled = magnification
            didApply = true
        }
        if let largeSize = doubleValue(forKey: "largesize", savedValues: savedValues, dockDefaults: dockDefaults) {
            settings.magnificationSize = clamped(largeSize, to: DockingSettingLimits.magnificationSize)
            didApply = true
        }

        return didApply
    }

    static func persistentDockItems(from dockDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock")) -> [DockItem] {
        var seenKeys: Set<String> = []
        let appItems = persistentAppItems(from: dockDefaults, seenKeys: &seenKeys)
        let otherItems = persistentOtherItems(from: dockDefaults, seenKeys: &seenKeys)
        return appItems + otherItems
    }

    private static func persistentAppItems(from dockDefaults: UserDefaults?, seenKeys: inout Set<String>) -> [DockItem] {
        dockDefaults?.array(forKey: "persistent-apps")?.compactMap { rawItem in
            guard let tileData = tileData(from: rawItem, tileType: "file-tile") else {
                return nil
            }

            let bundleIdentifier = tileData["bundle-identifier"] as? String
            let fileData = tileData["file-data"] as? [String: Any]
            let url = (fileData?["_CFURLString"] as? String).flatMap(URL.init(string:))
                ?? bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }

            guard let applicationURL = url, applicationURL.pathExtension == "app" else {
                return nil
            }

            let stableKey = "app:\(bundleIdentifier ?? applicationURL.standardizedFileURL.path)"
            guard !seenKeys.contains(stableKey) else {
                return nil
            }
            seenKeys.insert(stableKey)

            let title = (tileData["file-label"] as? String)?.nilIfBlank
                ?? applicationURL.deletingPathExtension().lastPathComponent
            return DockItem(
                kind: .application,
                title: title,
                bundleIdentifier: bundleIdentifier,
                url: applicationURL.standardizedFileURL,
                iconCacheKey: bundleIdentifier ?? "application:\(applicationURL.standardizedFileURL.path)"
            )
        } ?? []
    }

    private static func persistentOtherItems(from dockDefaults: UserDefaults?, seenKeys: inout Set<String>) -> [DockItem] {
        dockDefaults?.array(forKey: "persistent-others")?.compactMap { rawItem in
            guard let rawItem = rawItem as? [String: Any],
                  let type = rawItem["tile-type"] as? String, ["directory-tile", "file-tile"].contains(type),
                  let tileData = rawItem["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let url = (fileData["_CFURLString"] as? String).flatMap(URL.init(string:))?.standardizedFileURL,
                  url.isFileURL, let item = AppCatalogService.dockItemIfSupported(for: url), !item.isApplication else {
                return nil
            }

            let stableKey = item.identityKey
            guard !seenKeys.contains(stableKey) else {
                return nil
            }
            seenKeys.insert(stableKey)

            let title = (tileData["file-label"] as? String)?.nilIfBlank
                ?? AppCatalogService.localizedDisplayName(for: url)

            var imported = item
            imported.title = title
            if imported.isFolder {
                imported.folderDisplayMode = folderDisplayMode(from: tileData["displayas"])
                imported.folderViewMode = folderViewMode(from: tileData["showas"])
                imported.folderSortMode = folderSortMode(from: tileData["arrangement"])
            }
            return imported
        } ?? []
    }

    private static func tileData(from rawItem: Any, tileType: String) -> [String: Any]? {
        guard let item = rawItem as? [String: Any],
              item["tile-type"] as? String == tileType,
              let tileData = item["tile-data"] as? [String: Any] else {
            return nil
        }
        return tileData
    }

    private static func folderDisplayMode(from rawValue: Any?) -> DockFolderDisplayMode {
        intValue(rawValue) == 0 ? .stack : .folder
    }

    private static func folderViewMode(from rawValue: Any?) -> DockFolderViewMode {
        switch intValue(rawValue) {
        case 1:
            return .fan
        case 2:
            return .grid
        case 3:
            return .list
        default:
            return .automatic
        }
    }

    private static func folderSortMode(from rawValue: Any?) -> DockFolderSortMode {
        switch intValue(rawValue) {
        case 2:
            return .dateAdded
        case 3:
            return .dateModified
        case 4:
            return .dateCreated
        case 5:
            return .kind
        default:
            return .name
        }
    }

    private static func intValue(_ rawValue: Any?) -> Int? {
        if let value = rawValue as? Int {
            return value
        }
        if let value = rawValue as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func dockAutohideValue(from dockDefaults: UserDefaults?) -> Bool? {
        guard let rawValue = dockDefaults?.object(forKey: "autohide") else {
            return nil
        }

        if let value = rawValue as? Bool {
            return value
        }

        // The Dock preference domain is maintained by macOS and has historically
        // represented booleans as property-list numbers in some paths. Treating
        // NSNumber explicitly keeps this read-only seed robust without adding a
        // broader migration layer for Docking's own pre-1.0 settings format.
        if let value = rawValue as? NSNumber {
            return value.boolValue
        }

        return nil
    }

    private static func boolValue(forKey key: String, savedValues: [String: DockPreferenceValue]?, dockDefaults: UserDefaults?) -> Bool? {
        if case .bool(let value) = savedValues?[key] {
            return value
        }
        return (dockDefaults?.object(forKey: key) as? NSNumber)?.boolValue
    }

    private static func doubleValue(forKey key: String, savedValues: [String: DockPreferenceValue]?, dockDefaults: UserDefaults?) -> Double? {
        if case .double(let value) = savedValues?[key] {
            return value
        }

        let rawValue = dockDefaults?.object(forKey: key)
        if let value = rawValue as? Double {
            return value
        }
        if let value = rawValue as? Int {
            return Double(value)
        }
        if let value = rawValue as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    private static func stringValue(forKey key: String, savedValues: [String: DockPreferenceValue]?, dockDefaults: UserDefaults?) -> String? {
        if case .string(let value) = savedValues?[key] {
            return value
        }
        return dockDefaults?.string(forKey: key)
    }

    private static func dockPosition(forAppleDockOrientation orientation: String) -> DockPosition? {
        switch orientation {
        case "bottom":
            return .bottomCenter
        case "left":
            return .left
        case "right":
            return .right
        default:
            return nil
        }
    }

    private static func clamped<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
