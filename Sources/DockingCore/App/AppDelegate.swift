import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // The app is not menu-bar-only: it owns a visible dock-like panel and
        // one Control Center window. A regular activation policy keeps
        // permissions prompts, Control Center, and file panels behaving like a
        // normal macOS app.
        NSApp.setActivationPolicy(.regular)
        DockingIconAssets.applyApplicationIcon()
        Task { @MainActor in
            // SwiftUI is still constructing the WindowGroup when AppKit calls
            // `applicationDidFinishLaunching`. Starting the model immediately
            // publishes the running-app snapshot, restore status, and menu-bar
            // state while those views are in their first update pass, which
            // triggers SwiftUI's "Publishing changes from within view updates"
            // runtime warning. Yielding one main-actor turn keeps launch just as
            // fast for the user, but lets the scene finish before Docking starts
            // its own resident panels and observer-driven state updates.
            await Task.yield()
            DockingAppModel.shared.start()
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the Control Center window should not quit a dock utility.
        // The user has explicit Quit paths in the menu bar and Control Center's
        // Restore section, which avoids accidental loss of the dock surface.
        false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Control Center writes are debounced during normal interaction to
        // avoid disk churn from sliders. Termination is the one place where
        // immediacy is more important than batching, because the app will not
        // get another chance to persist the final visible state.
        DockingAppModel.shared.flushPendingSettingsSave()
    }
}
