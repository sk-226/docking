# Dock parity notes

Docking is not trying to clone private Dock internals, but the right-click menu
should cover the public, everyday app-control actions users expect from the
macOS Dock. This file keeps that scope explicit while the app is still `0.0.0`.

## App icon context menu

| Capability | Docking status | Notes |
| --- | --- | --- |
| Open | Implemented | Opens the app through `NSWorkspace`, not shell commands. |
| Drop a document onto an app icon to open it in that app | Implemented | Ordinary files dropped on an app icon are opened through LaunchServices with that app. Dragged `.app` bundles and folders remain Docking item additions so app/folder placement stays predictable. |
| Show All Windows | Implemented as activate all windows | Public AppKit does not expose Dock's Mission Control window picker. Docking activates the app with all windows instead of using private APIs. |
| Hide | Implemented | Uses `NSRunningApplication.hide()` for running apps. |
| Quit | Implemented | Uses `NSRunningApplication.terminate()` so apps can handle their own save prompts. |
| Force Quit | Implemented with confirmation | Uses `NSRunningApplication.forceTerminate()` only after a destructive confirmation. |
| Keep in Docking | Implemented for transient running apps | Converts a running unpinned app into a pinned Docking item. |
| Remove from Docking | Implemented for pinned apps | Removes only Docking's pinned item, not the application bundle. |
| Show in Finder | Implemented | Reveals the app bundle when Docking can resolve it. |
| Open Control Center | Implemented under Docking submenu | Docking-specific configuration stays separate from the standard Dock-style Open/Show/Hide/Quit/Options stack. |
| Open at Login for arbitrary apps | Not implemented | macOS exposes safe public login-item APIs primarily for the current app/helper. Changing login items for arbitrary third-party apps from Docking would be surprising and fragile. |
| Assign to Desktop / All Desktops | Not implemented | Spaces assignment is Dock/System UI behavior without a stable public API suitable for a third-party dock. |
| App-specific recent documents or New Window actions | Not implemented | Those actions are app-specific and require per-app integration rather than a generic dock item model. |

## Folder / stack context menu

Apple's Dock treats folders as stack items stored separately from app tiles. In
Docking, ordinary directories can be added from the picker, Finder drag/drop, or
Apple Dock mirroring from `persistent-others`.

| Capability | Docking status | Notes |
| --- | --- | --- |
| Click to show contents | Implemented | Opens a Docking stack panel anchored to the folder icon instead of launching Finder. |
| Click again to close | Implemented | The source icon is exempt from outside-click dismissal so the same click path can close the panel. |
| Open | Implemented | Opens the folder in Finder through `NSWorkspace.open`. |
| Sort By: Name / Date Added / Date Modified / Date Created / Kind | Implemented | Sort state is saved per folder item and drives stack-panel ordering and stack-preview icons. |
| Display as: Folder / Stack | Implemented | Folder uses the system folder icon; Stack composes a small preview from folder contents. |
| View content as: Automatic / Fan / Grid / List | Implemented | Fan/Grid/List change the Docking panel presentation; Automatic chooses based on item count without using private Dock geometry. |
| Stack entry Open | Implemented | Open is available both by normal click and by the entry context menu. |
| Stack entry Show in Finder | Implemented | Reveals the real item URL in Finder, then closes the transient stack panel. |
| Drag stack entries to other apps | Implemented | Stack entries vend `public.file-url` through `NSItemProvider`, leaving the receiving app/Finder to decide open/import/copy/move semantics. |
| Remove from Docking | Implemented | Removes the Docking item only; it never deletes the folder. |
| Show in Finder | Implemented | Reveals the folder location in Finder. |
| Drop files onto a Dock folder to copy/move into that folder | Implemented | Option copies; otherwise same-volume drops move and cross-volume drops copy. Existing-name collisions and recursive folder drops fail with a visible alert instead of overwriting or producing low-level errors. |
| Documents or arbitrary files as Dock items | Not implemented | The Apple Dock can hold some non-folder items in persistent-others, but Docking keeps this 0.0.0 item model to apps and folders until the UI intentionally supports document launching. |

## Quality bar

- Process actions appear only when Docking believes the app is running.
- Process actions do not appear for folder items.
- Ordinary file drops on an app icon open with that app; app bundles and
  folders still add/reorder Docking items instead of becoming app inputs.
- Folder context menus expose the stack-specific display, view, and sorting
  choices users expect from the macOS Dock.
- Stack entry menus and drags operate on the real file URLs, not copied cache
  files or Docking-private proxies.
- Dropping files onto a Dock folder mutates the real destination folder only
  after routing through explicit folder-drop logic, not through the add-to-Dock
  target path.
- Force Quit always shows a confirmation before termination.
- Docking never removes an app bundle from disk.
- Docking never removes a folder from disk.
- Docking avoids private Dock or Mission Control APIs even when that means an
  action is an approximation rather than a pixel-for-pixel Dock clone.
