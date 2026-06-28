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
- The source/docs search returns no matches. `QA.md` is intentionally excluded
  because it documents the search expression itself.

## Manual gates before GitHub cutover

| Area | Steps | Pass condition | Status |
| --- | --- | --- | --- |
| First launch | Run `./script/build_and_run.sh --verify`, then open the main window and Settings. | Dock panel appears, menu bar item works, Settings opens without crash. | Not yet manually verified |
| Calendar permission not requested while disabled | Turn Calendar widget off, reopen Settings > Widgets. | No Calendar permission prompt appears. | Not yet manually verified |
| Calendar permission granted | Turn Calendar widget on and grant Calendar access. | Detail panel shows grouped events or a clear empty state. | Not yet manually verified |
| Calendar permission denied | Deny Calendar access in System Settings, then open the widget. | Detail panel shows a permission state and does not crash. | Not yet manually verified |
| Weather manual city | Disable current location, set a city such as `Tokyo`, open Weather. | Real weather loads or a provider/network error is shown with no mock values. | Not yet manually verified |
| Weather location denial | Enable current location and deny Location Services. | Weather shows the location-denied state and does not silently fall back to fake data. | Not yet manually verified |
| App launcher | Add an `.app`, launch it from Docking, remove it, reset the list. | Icon loads once, app opens through `NSWorkspace`, running indicator updates. | Not yet manually verified |
| Reorder/drop | Reorder apps inside the dock and drop an external `.app`. | Ordering persists and non-application drops are ignored. | Not yet manually verified |
| Auto-hide | Enable auto-hide and move the pointer away, then to the screen edge. | Dock hides after the configured delay and reappears through the edge trigger. | Not yet manually verified |
| Spaces/full-screen | Toggle all-Spaces/full-screen settings and move through Spaces/full-screen apps. | Dock remains available without stealing focus. | Not yet manually verified |
| Multiple displays | Test main, pointer, and specific display modes. | Dock stays inside the selected display's visible frame and falls back safely if disconnected. | Not yet manually verified |
| Sleep/wake | Put the Mac to sleep and wake it with Docking running. | Dock repositions, running app state refreshes, widgets remain responsive. | Not yet manually verified |
| Restore safety | Open Settings > Restore, inspect primary mode, restore, disable, and reload controls. Do not confirm reload unless intentionally testing Apple Dock restart. | Primary mode explains snapshot/restore behavior; reload shows a confirmation before `killall Dock`; restore/disable do not crash. | Not yet manually verified |
| Idle performance | Leave pointer away from the dock for several minutes in Activity Monitor. | CPU stays close to 0% and memory remains stable. | Not yet manually verified |
| Network cadence | Open Weather once and observe logs/network. | Refreshes do not repeat every few seconds. | Not yet manually verified |

## Git/GitHub readiness

Start the GitHub handoff only after:

- All automated gates pass on the current worktree.
- Manual gates above are either passed or deliberately recorded as known
  limitations in `README.md`.
- The worktree has no unrelated local changes mixed into the app milestone.
- The branch/commit message states that this is a `0.0.0` pre-release native
  macOS app and that Apple Dock preferences remain overlay-only until the user
  explicitly enables primary dock mode.
