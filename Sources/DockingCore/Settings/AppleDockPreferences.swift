import AppKit
import Foundation

enum AppleDockPreferences {
    static func visibilityMode(from dockDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock")) -> DockVisibilityMode {
        guard let autohide = dockAutohideValue(from: dockDefaults) else {
            // If the Dock domain cannot be read, prefer the mode the user asked
            // for in this 0.0.0 build: Docking should behave like an auto-hide
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
            // Apple Dock's tile size maps most closely to the app icon, while
            // Docking also needs room for running indicators and compact
            // widgets. Keeping the existing widget readability floor avoids
            // recreating the Calendar-overlap bug when a user's Apple Dock is
            // very small.
            let readableDockSize = max(iconSize + 26, DockingSettingLimits.widgetReadableMinimum + 14)
            settings.dockSize = clamped(readableDockSize, to: DockingSettingLimits.dockSize)
            didApply = true
        }

        return didApply
    }

    static func persistentAppItems(from dockDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock")) -> [DockItem] {
        guard let rawItems = dockDefaults?.array(forKey: "persistent-apps") else {
            return []
        }

        var seenKeys: Set<String> = []
        return rawItems.compactMap { rawItem in
            guard let item = rawItem as? [String: Any],
                  item["tile-type"] as? String == "file-tile",
                  let tileData = item["tile-data"] as? [String: Any] else {
                return nil
            }

            let bundleIdentifier = tileData["bundle-identifier"] as? String
            let fileData = tileData["file-data"] as? [String: Any]
            let url = (fileData?["_CFURLString"] as? String).flatMap(URL.init(string:))
                ?? bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }

            guard let appURL = url, appURL.pathExtension == "app" else {
                return nil
            }

            let stableKey = bundleIdentifier ?? appURL.path
            guard !seenKeys.contains(stableKey) else {
                return nil
            }
            seenKeys.insert(stableKey)

            let title = (tileData["file-label"] as? String)?.nilIfBlank
                ?? appURL.deletingPathExtension().lastPathComponent
            return DockItem(
                title: title,
                bundleIdentifier: bundleIdentifier,
                appURL: appURL,
                iconCacheKey: stableKey
            )
        }
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
        // broader migration layer for Docking's own 0.0.0 settings format.
        if let value = rawValue as? NSNumber {
            return value.boolValue
        }

        return nil
    }

    private static func boolValue(forKey key: String, savedValues: [String: DockPreferenceValue]?, dockDefaults: UserDefaults?) -> Bool? {
        if case .bool(let value) = savedValues?[key] {
            return value
        }
        return dockAutohideValue(from: key == "autohide" ? dockDefaults : nil)
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
