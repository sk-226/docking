import AppKit

enum DockingIconAssets {
    static func applyApplicationIcon() {
        guard let icon = appIcon() else {
            return
        }

        NSApplication.shared.applicationIconImage = icon
    }

    static func menuBarIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "DockingMenuBarTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            // The PNG is rendered at 2x so the glyph stays crisp on Retina menu
            // bars, but AppKit sizes status-item images in points. Setting the
            // logical size here avoids an oversized menu bar item while keeping
            // the asset simple enough to be copied directly into the SwiftPM-
            // staged app bundle.
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }

        // Keep a system fallback for raw SwiftPM launches or partially staged
        // development bundles. The normal run script copies the custom resource,
        // but this fallback makes the status item fail soft instead of becoming
        // invisible when someone launches the executable outside the bundle.
        let fallback = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Docking") ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }

    private static func appIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "DockingAppIcon", withExtension: "icns") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}
