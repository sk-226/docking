# Docking QA checklist

This checklist tracks evidence that cannot be fully proven by SwiftPM builds or
the framework-free validation executable. Keep it current before cutting a
GitHub branch or pull request for a user-facing milestone.

## Automated gates

Run this after each meaningful code change:

```bash
./script/release_check.sh
```

The scratch paths intentionally use the lowercase `docking-app` internal name.
The product and bundle remain `Docking`; the lowercase temporary directory
avoids Swift/Clang module-cache collisions on case-insensitive macOS volumes
when earlier pre-rename builds used lowercase paths.

Expected results:

- `DockingValidation` prints `All Docking validation checks passed.`
- A release app bundle is staged at `dist/Docking.app`.
- A local release-candidate zip is written to `dist/Docking-0.0.0-macos26.zip`.
- Both bundle version values are `0.0.0`.
- The bundle identifier is `app.docking.docking`.
- The bundle minimum system version is `26.0`.
- `codesign --verify --deep` accepts the staged app bundle.
- The source/docs search returns no matches. `QA.md` is intentionally excluded
  because this file documents the automated gate itself.
- The user-specific identifier/path search returns no matches. It intentionally
  excludes build output and `.git` so the check covers authored project files,
  not previous binaries or history.
- The final release identity section prints the current branch, short commit,
  worktree cleanliness, and SHA-256 for `dist/Docking-0.0.0-macos26.zip`.

`./script/build_and_run.sh --verify` remains the quick launch smoke test. The
release gate packages without launching so an artifact inspection does not also
change app windows, permissions, or local user defaults.

Latest automated evidence: passed 2026-06-29 on the current release-candidate
path. The run created `dist/Docking-0.0.0-macos26.zip`, verified the staged app
signature, and confirmed that unprovisioned builds omit the WeatherKit
entitlement so Weather uses the Open-Meteo real-data fallback instead of failing
at launch.

## Manual gates before GitHub cutover

| Area | Steps | Pass condition | Status |
| --- | --- | --- | --- |
| First launch | Run `./script/build_and_run.sh --verify`, then open Control Center from the app menu and menu bar item. | Dock panel appears, menu bar item works, Control Center opens without crash. | Passed 2026-06-28 via `--verify` and Computer Use: Overview, app menu, and Control Center opened without crash. |
| Calendar permission not requested while disabled | Turn Calendar widget off, reopen Control Center > Widgets. | No Calendar permission prompt appears. | Passed 2026-06-28 via Computer Use: disabling the Calendar widget kept the Widgets tab stable, disabled the Load button, showed `Enable the Calendar widget to choose calendars.`, and did not show a macOS permission prompt. Validation also covers disabled direct refresh/source load/store-change paths. |
| Calendar permission granted | Turn Calendar widget on and grant Calendar access. | Detail panel shows grouped events or a clear empty state. | Not yet manually verified |
| Calendar permission denied | Deny Calendar access in System Settings, then open the widget. | Detail panel shows a permission state and does not crash. | Partially covered 2026-06-29 by validation: denied authorization publishes `permissionDenied`, restricted publishes `permissionRestricted`, write-only publishes `permissionWriteOnly`, compact text becomes `Off` / `Calendar`, detail/source copy stays permission-specific, and direct refresh/source loading do not crash. Live System Settings denial is still not yet manually verified. |
| Weather manual city | Disable current location, set a city such as `Tokyo`, open Weather. | Real weather loads or a provider/network error is shown with no mock values. | Passed 2026-06-28 via Computer Use: manual city `Tokyo` showed real weather for `Tokyo, Tokyo, Japan`, updated at 19:05, with temperature, condition, hourly/daily forecast, and humidity. Missing manual city with cached data now shows a stale-cache message instead of a contradictory bare city prompt. |
| Weather location denial | Enable current location and deny Location Services. | Weather shows the location-denied state and does not silently fall back to fake data. | Partially covered 2026-06-28 by validation: current-location denial with no manual fallback publishes `locationDenied` and no fabricated snapshot; with cached weather it shows stale cached data; with a manual city it falls back to the configured city. Live Location Services denial is still not yet manually verified. |
| App launcher and process actions | Add an `.app`, launch it from Docking, Command-click it, right-click it, use Show All Windows and Hide, use Quit, Option-open the menu for Force Quit, drop a document onto the app icon, remove it, reset the list. | Icon loads once, normal click opens through `NSWorkspace`, Command-click reveals the app in Finder, document drops open through that app instead of adding arbitrary files to Docking, running indicator updates, Show All Windows activates the app, Hide hides it, Quit requests graceful termination, Force Quit replaces Quit instead of appearing beside it, and Docking-specific actions live under the Docking submenu. | Passed 2026-06-28 via Computer Use and validation: previous Computer Use confirmed Open, Show All Windows, Hide, Quit, Finder reveal, removal, Force Quit confirmation, and disposable DockingProbe termination. Current validation covers normal `Quit` vs Option-modified `Force Quit...` as mutually exclusive menu titles, and live context-menu inspection showed `Open`, `Show All Windows`, `Hide`, `Quit`, `Options > Keep in Docking / Show in Finder`, and `Docking > Open Control Center`. Command-click reveal and document-drop-to-app behavior are implemented but still need live UI verification. |
| Folder stacks | Add a folder from the picker or Finder drop, click it, right-click it, change Sort By, Display as, and View content as. Use Primary Dock match on a Dock with Applications/Downloads folders. Right-click and drag an item from an open stack. Drop a temporary file onto a Dock folder icon. | Folder click opens a stack panel anchored to the folder icon; clicking the same icon closes it; Open opens Finder; Sort By/Display as/View content as affect the item; Remove from Docking never deletes the folder; Primary Dock match imports `persistent-others`; Downloads initially shows 12 visible items, loads more while scrolling, and updates the header count as the user scrolls back up/down; stack entries expose Open/Show in Finder and drag their real file URL to other Mac apps; folder icon drops copy/move into the real folder using Finder-style same-volume/Option semantics. | Partially covered 2026-06-29 by validation and screenshot review: Apple Dock mirroring imports `persistent-others` directory tiles with `displayas`/`showas`/`arrangement`; app catalog accepts folders and rejects plain files; folder stack sorting and Automatic/Fan/Grid/List presentation resolve correctly; Downloads recent sorting keeps a 12-item initial page and full older list for scroll reveal; generated Dock icons use the full Retina backing so the Downloads icon stays centered and app-sized; Downloads header range updates back to `1-12` when scrolled to the top of loaded entries and advances to `25-36` lower in the loaded grid; Downloads page reveal now uses scroll geometry rather than requiring SwiftUI `ScrollPhase`, so trackpad/wheel inertia in the non-activating stack panel is less likely to miss additional pages. Stack entry context menus, file-url drag providers, and folder-drop file operations are implemented, but live Finder drag/drop is still not yet manually verified. |
| Unpinned running apps | Launch an app that is not kept in Docking, such as Zed, then toggle Control Center > General > Unpinned running apps. | The running app appears once in a separated section when enabled and disappears when hidden; pinned apps are not duplicated. | Passed 2026-06-28 via Computer Use: Overview showed 5 running unpinned apps; General showed `Show separated`; Dock AX tree showed Zed once in the transient section. |
| Appearance presets | Open Control Center > Appearance, switch Dock scale, Calendar widget, Weather widget, and Liquid Glass presets. | Appearance uses compact preset controls rather than raw visual sliders; Calendar and Weather widget sizes are independent; larger widgets spend horizontal space and do not increase dock vertical occupation; Liquid Glass has a live preview. | Partially passed 2026-06-28 via Computer Use: Appearance showed Dock scale, Calendar widget, Weather widget, and Liquid Glass segmented controls with a side preview; switching Calendar to Detailed widened the preview without increasing its vertical footprint. Validation covers detailed widget presets using horizontal layout and staying within the dock tile height. Live Dock-panel screenshot verification remains partially limited by the non-activating panel capture path. |
| Dock accessibility | Show the Dock and inspect the accessibility tree. | Each dock item exposes its own name, running/folder state, and button role; the dock group label does not replace child labels. | Passed 2026-06-28 via Computer Use: dock items reported `button` with app-specific descriptions such as Finder, Zed, Calendar, Weather, and the add item control. |
| Widget panel toggle | Open Calendar or Weather from Docking's Dock, then click the same widget again. | Detail panel opens without crashing; clicking the same widget closes it; Dock remains reachable while the panel is open. | Passed 2026-06-28: Computer Use confirmed the Weather detail panel opens through the same model action, and the user verified that clicking the widget again closes the panel. Validation covers same-click retoggle suppression so outside-click dismissal cannot immediately reopen the same widget. |
| Reorder/drop | Reorder items inside the dock and drop an external `.app` or folder. | Ordering persists; app bundles become application items; folders become folder stack items; unsupported plain files are ignored. | Partially passed 2026-06-29 via Computer Use and validation: Items tab reorder still uses explicit up/down controls; validation covers `.app` bundle drops preserving app metadata, folder drops creating stack items, and plain file drops being rejected. Live Finder-to-Docking drag/drop is still not yet manually verified. |
| Auto-hide | Enable auto-hide and move the pointer away, then to the screen edge. | Dock hides after the configured delay and reappears through the edge trigger. | Partially covered 2026-06-28 by validation and implementation review: bottom dock edge triggers are installed for every connected display, touch the physical screen edge, and use trigger-view tracking plus a global mouse-move fallback when another app owns the frontmost event stream. Computer Use confirmed Hide/Show controls and WindowServer confirmed edge panels on both displays; physical pointer-edge reveal is still not yet manually verified because synthetic pointer movement did not produce normal `NSEvent` delivery. |
| Explicit Show Dock in auto-hide | Enable auto-hide, press Show Dock, close Control Center, and wait beyond the configured delay. | A stale auto-hide task must not immediately hide a dock the user explicitly asked to show. | Passed 2026-06-28 via Computer Use: pressing Show Dock in auto-hide mode, closing Control Center, and waiting beyond the 0.7s delay left the Docking Dock visible and accessible. |
| Keep above windows | Toggle Control Center > General > Keep above other windows off and on. | Docking uses ordinary window level when off and floating dock level when on, without stealing focus. | Passed 2026-06-28 via Computer Use and validation: General toggle changed OFF and back ON without crashing or moving settings; `DockPanelController.windowLevel(for:)` validates `.normal` when off and `.floating` when on while the panel remains non-activating. |
| Spaces/full-screen | Toggle all-Spaces/full-screen settings and move through Spaces/full-screen apps. | Dock remains available without stealing focus. | Partially covered 2026-06-28 by validation: dock and edge-trigger panels share the same transient/ignores-cycle collection behavior; default settings include all-Spaces and full-screen auxiliary flags, and turning the toggles off removes those flags. Live Space/full-screen movement is still not yet manually verified. |
| Multiple displays | Test main, pointer, and specific display modes. | Dock stays inside the selected display's visible frame and falls back safely if disconnected. | Partially covered 2026-06-28 by validation: specific display selection resolves to a usable dock frame, disconnected specific displays fall back, and bottom auto-hide creates edge triggers for all connected displays. Live multi-monitor movement is still not yet manually verified. |
| Sleep/wake | Put the Mac to sleep and wake it with Docking running. | Dock repositions, running app state refreshes, widgets remain responsive. | Partially covered 2026-06-28 by implementation review: Docking observes `NSWorkspace.didWakeNotification`, reapplies window settings, refreshes the running-app snapshot once, and calls calendar/weather `refreshIfNeeded`. Actual machine sleep/wake is still not yet manually verified. |
| Restore safety | Open Control Center > Restore, inspect primary mode, match-original-layout, restore, disable, and reload controls. Do not confirm reload unless intentionally testing Apple Dock restart. | Primary mode explains snapshot/restore behavior; match-original-layout imports readable Apple Dock layout into Docking; enable, disable, restore, and reload all show confirmation before changing Apple Dock preferences or restarting Dock; restore/disable do not crash. | Partially passed 2026-06-29 via implementation review and Computer Use: Restore displayed snapshot time, restore/manual instructions, reload button, and Quit; dangerous Apple Dock actions now use confirmation dialogs. `killall Dock` confirmation/reload was not executed. |
| Idle performance | Leave pointer away from the dock for several minutes in Activity Monitor. | CPU stays close to 0% and memory remains stable. | Partially covered by short `ps` sampling of the live `Docking` process. 2026-06-29 sample after `./script/build_and_run.sh --verify`: startup-adjacent CPU was 1.3% with RSS 165,536 KB, then settled to 0.0% CPU with RSS about 158,900 KB across a 30-second idle window. Longer Activity Monitor observation is still not yet manually verified. |
| Network cadence | Open Weather once and observe logs/network. | Refreshes do not repeat every few seconds. | Partially covered 2026-06-28 by validation: fresh cached weather suppresses passive `refreshIfNeeded` and non-forced refresh provider calls, while forced manual refresh still works. Live log/network observation is still not yet manually verified. |

## Git/GitHub readiness

Start the GitHub handoff only after:

- All automated gates pass on the current worktree.
- Manual gates above are either passed or deliberately recorded as known
  limitations in `README.md`.
- The worktree has no unrelated local changes mixed into the app milestone.
- The branch/commit message states that this is a `0.0.0` pre-release native
  macOS app and that Apple Dock preferences remain overlay-only until the user
  explicitly enables primary dock mode.
