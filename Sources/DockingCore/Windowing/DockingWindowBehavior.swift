import AppKit

enum DockingWindowBehavior {
    static func collectionBehavior(for settings: DockingSettings) -> NSWindow.CollectionBehavior {
        // Docking uses multiple AppKit panels for one product surface: the
        // visible dock and the invisible auto-hide edge triggers. They must
        // share Spaces/full-screen policy or users can end up with a visible
        // dock that cannot be revealed, or a trigger that exists in a Space
        // where the dock panel itself is not allowed to appear. Keeping this in
        // one helper avoids that drift without creating a larger windowing
        // abstraction than the pre-1.0 app needs.
        var behavior: NSWindow.CollectionBehavior = [.transient, .ignoresCycle]
        if settings.showOnAllSpaces {
            behavior.insert(.canJoinAllSpaces)
        }
        if settings.showOnFullScreenSpaces {
            behavior.insert(.fullScreenAuxiliary)
        }
        return behavior
    }
}
