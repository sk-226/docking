import AppKit
import Foundation

@MainActor
final class AppLauncherService {
    func open(_ item: DockItem) {
        guard let url = resolvedURL(for: item) else {
            DockingLog.dock.error("Could not resolve app URL for \(item.title)")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        // NSWorkspace handles activation, app reuse, and bundle semantics better
        // than shelling out to `open`. Avoiding shell commands also keeps launch
        // behavior testable and avoids surprising quoting/path edge cases.
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                DockingLog.dock.error("Failed to launch \(item.title): \(error.localizedDescription)")
            }
        }
    }

    func showInFinder(_ item: DockItem) {
        guard let url = resolvedURL(for: item) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func resolvedURL(for item: DockItem) -> URL? {
        if let appURL = item.appURL {
            return appURL
        }
        if let bundleIdentifier = item.bundleIdentifier {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }
        return nil
    }
}
