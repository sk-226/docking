import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // The app is not menu-bar-only: it owns a visible dock-like panel and
        // Settings window. A regular activation policy keeps permissions prompts,
        // settings, and file panels behaving like a normal macOS app.
        NSApp.setActivationPolicy(.regular)
        DockingAppModel.shared.start()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the control/settings windows should not quit a dock utility.
        // The user has explicit Quit paths in the menu bar and Settings restore
        // section, which avoids accidental loss of the dock surface.
        false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Settings writes are debounced during normal interaction to avoid disk
        // churn from sliders. Termination is the one place where immediacy is
        // more important than batching, because the app will not get another
        // chance to persist the final visible state.
        DockingAppModel.shared.flushPendingSettingsSave()
    }
}
