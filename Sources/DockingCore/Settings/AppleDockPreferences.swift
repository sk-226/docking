import Foundation

enum AppleDockPreferences {
    static func visibilityMode(from dockDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock")) -> DockVisibilityMode {
        guard let autohide = dockAutohideValue(from: dockDefaults) else {
            // If the Dock domain cannot be read, prefer the mode the user asked
            // for in this 0.0.0 build: Docking should behave like an auto-hide
            // dock instead of permanently covering the workspace. This is a
            // product default, not a compatibility fallback.
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
}
