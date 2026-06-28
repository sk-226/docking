# Dock parity notes

Docking is not trying to clone private Dock internals, but the right-click menu
should cover the public, everyday app-control actions users expect from the
macOS Dock. This file keeps that scope explicit while the app is still `0.0.0`.

## App icon context menu

| Capability | Docking status | Notes |
| --- | --- | --- |
| Open | Implemented | Opens the app through `NSWorkspace`, not shell commands. |
| Show All Windows | Implemented as activate all windows | Public AppKit does not expose Dock's Mission Control window picker. Docking activates the app with all windows instead of using private APIs. |
| Hide | Implemented | Uses `NSRunningApplication.hide()` for running apps. |
| Quit | Implemented | Uses `NSRunningApplication.terminate()` so apps can handle their own save prompts. |
| Force Quit | Implemented with confirmation | Uses `NSRunningApplication.forceTerminate()` only after a destructive confirmation. |
| Keep in Docking | Implemented for transient running apps | Converts a running unpinned app into a pinned Docking item. |
| Remove from Docking | Implemented for pinned apps | Removes only Docking's pinned item, not the application bundle. |
| Show in Finder | Implemented | Reveals the app bundle when Docking can resolve it. |
| Open Control Center | Implemented | Provides the settings path that replaces the standard Dock's app-specific Options submenu. |
| Open at Login for arbitrary apps | Not implemented | macOS exposes safe public login-item APIs primarily for the current app/helper. Changing login items for arbitrary third-party apps from Docking would be surprising and fragile. |
| Assign to Desktop / All Desktops | Not implemented | Spaces assignment is Dock/System UI behavior without a stable public API suitable for a third-party dock. |
| App-specific recent documents or New Window actions | Not implemented | Those actions are app-specific and require per-app integration rather than a generic dock item model. |

## Quality bar

- Process actions appear only when Docking believes the app is running.
- Force Quit always shows a confirmation before termination.
- Docking never removes an app bundle from disk.
- Docking avoids private Dock or Mission Control APIs even when that means an
  action is an approximation rather than a pixel-for-pixel Dock clone.
