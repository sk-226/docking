# Docking QA checklist

This checklist tracks evidence that cannot be fully proven by SwiftPM builds or
the framework-free validation executable. Keep it current before cutting a
GitHub branch or pull request for a user-facing milestone.

## Automated gates

Run these after each meaningful code change:

```bash
swift run --scratch-path /private/tmp/docking-app-swiftpm-validation DockingValidation
swift build -c release --product Docking --scratch-path /private/tmp/docking-app-swiftpm-release
./script/build_and_run.sh --verify
/usr/libexec/PlistBuddy -c Print:CFBundleShortVersionString dist/Docking.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c Print:CFBundleVersion dist/Docking.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c Print:LSMinimumSystemVersion dist/Docking.app/Contents/Info.plist
rg -n "#available|backward|compatib|decodeIfPresent|legacy|deprecated|requestAccess\\(to:" Sources Validation README.md PERFORMANCE.md Package.swift script
```

The scratch paths intentionally use the lowercase `docking-app` internal name.
The product and bundle remain `Docking`; the lowercase temporary directory
avoids Swift/Clang module-cache collisions on case-insensitive macOS volumes
when earlier pre-rename builds used lowercase paths.

Expected results:

- `DockingValidation` prints `All Docking validation checks passed.`
- Release build succeeds without relying on DEBUG-only mock weather data.
- `--verify` exits successfully and leaves a `Docking` process running.
- Both bundle version values are `0.0.0`.
- The bundle minimum system version is `26.0`.
- The source/docs search returns no matches. `QA.md` is intentionally excluded
  because it documents the search expression itself.

## Manual gates before GitHub cutover

| Area | Steps | Pass condition | Status |
| --- | --- | --- | --- |
| First launch | Run `./script/build_and_run.sh --verify`, then open Control Center from the app menu and menu bar item. | Dock panel appears, menu bar item works, Control Center opens without crash. | Passed 2026-06-28 via `--verify` and Computer Use: Overview, app menu, and Control Center opened without crash. |
| Calendar permission not requested while disabled | Turn Calendar widget off, reopen Control Center > Widgets. | No Calendar permission prompt appears. | Passed 2026-06-28 via Computer Use: disabling the Calendar widget kept the Widgets tab stable, disabled the Load button, showed `Enable the Calendar widget to choose calendars.`, and did not show a macOS permission prompt. Validation also covers disabled direct refresh/source load/store-change paths. |
| Calendar permission granted | Turn Calendar widget on and grant Calendar access. | Detail panel shows grouped events or a clear empty state. | Not yet manually verified |
| Calendar permission denied | Deny Calendar access in System Settings, then open the widget. | Detail panel shows a permission state and does not crash. | Not yet manually verified |
| Weather manual city | Disable current location, set a city such as `Tokyo`, open Weather. | Real weather loads or a provider/network error is shown with no mock values. | Passed 2026-06-28 via Computer Use: manual city `Tokyo` showed real weather for `Tokyo, Tokyo, Japan`, updated at 19:05, with temperature, condition, hourly/daily forecast, and humidity. Missing manual city with cached data now shows a stale-cache message instead of a contradictory bare city prompt. |
| Weather location denial | Enable current location and deny Location Services. | Weather shows the location-denied state and does not silently fall back to fake data. | Not yet manually verified |
| App launcher and process actions | Add an `.app`, launch it from Docking, right-click it, use Show All Windows and Hide, use Quit or Force Quit on a disposable app, remove it, reset the list. | Icon loads once, app opens through `NSWorkspace`, running indicator updates, Show All Windows activates the app, Hide hides it, Quit requests graceful termination, and Force Quit shows a confirmation before terminating. | Passed 2026-06-28 via Computer Use: Finder menu exposed Open, Show All Windows, Hide, Quit, Force Quit, Finder reveal, removal, and Control Center actions; disposable DockingProbe appeared as an unpinned running app, Force Quit showed confirmation, then the app disappeared and `pgrep -x DockingProbe` had no match. |
| Unpinned running apps | Launch an app that is not kept in Docking, such as Zed, then toggle Control Center > General > Unpinned running apps. | The running app appears once in a separated section when enabled and disappears when hidden; pinned apps are not duplicated. | Passed 2026-06-28 via Computer Use: Overview showed 5 running unpinned apps; General showed `Show separated`; Dock AX tree showed Zed once in the transient section. |
| Dock accessibility | Show the Dock and inspect the accessibility tree. | Each dock item exposes its own name, running state, and button role; the dock group label does not replace child labels. | Passed 2026-06-28 via Computer Use: dock items reported `button` with app-specific descriptions such as Finder, Zed, Calendar, Weather, and Add application. |
| Widget panel toggle | Open Calendar or Weather from Docking's Dock, then click the same widget again. | Detail panel opens without crashing; clicking the same widget closes it; Dock remains reachable while the panel is open. | Passed 2026-06-28: Computer Use confirmed the Weather detail panel opens through the same model action, and the user verified that clicking the widget again closes the panel. Validation covers same-click retoggle suppression so outside-click dismissal cannot immediately reopen the same widget. |
| Reorder/drop | Reorder apps inside the dock and drop an external `.app`. | Ordering persists and non-application drops are ignored. | Not yet manually verified |
| Auto-hide | Enable auto-hide and move the pointer away, then to the screen edge. | Dock hides after the configured delay and reappears through the edge trigger. | Partially covered 2026-06-28 by validation: bottom dock edge triggers are installed for every connected display and touch the physical screen edge; side docks stay scoped to the selected display. Live pointer-edge reveal is still not yet manually verified. |
| Explicit Show Dock in auto-hide | Enable auto-hide, press Show Dock, close Control Center, and wait beyond the configured delay. | A stale auto-hide task must not immediately hide a dock the user explicitly asked to show. | Passed 2026-06-28 via Computer Use: pressing Show Dock in auto-hide mode, closing Control Center, and waiting beyond the 0.7s delay left the Docking Dock visible and accessible. |
| Keep above windows | Toggle Control Center > General > Keep above other windows off and on. | Docking uses ordinary window level when off and floating dock level when on, without stealing focus. | Not yet manually verified |
| Spaces/full-screen | Toggle all-Spaces/full-screen settings and move through Spaces/full-screen apps. | Dock remains available without stealing focus. | Not yet manually verified |
| Multiple displays | Test main, pointer, and specific display modes. | Dock stays inside the selected display's visible frame and falls back safely if disconnected. | Partially covered 2026-06-28 by validation: specific display selection resolves to a usable dock frame, disconnected specific displays fall back, and bottom auto-hide creates edge triggers for all connected displays. Live multi-monitor movement is still not yet manually verified. |
| Sleep/wake | Put the Mac to sleep and wake it with Docking running. | Dock repositions, running app state refreshes, widgets remain responsive. | Not yet manually verified |
| Restore safety | Open Control Center > Restore, inspect primary mode, match-original-layout, restore, disable, and reload controls. Do not confirm reload unless intentionally testing Apple Dock restart. | Primary mode explains snapshot/restore behavior; match-original-layout imports readable Apple Dock layout into Docking; reload shows a confirmation before `killall Dock`; restore/disable do not crash. | Partially passed 2026-06-28 via Computer Use: Restore displayed snapshot time, restore/manual instructions, reload button, and Quit. `killall Dock` confirmation/reload was not executed. |
| Idle performance | Leave pointer away from the dock for several minutes in Activity Monitor. | CPU stays close to 0% and memory remains stable. | Not yet manually verified |
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
