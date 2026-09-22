# Docking QA checklist

This checklist tracks evidence that cannot be fully proven by SwiftPM builds or
the framework-free validation executable. Keep it current before cutting a
GitHub branch or pull request for a user-facing milestone.

## Automated gates

See [GitHub Releases](https://github.com/sk-226/docking/releases) for published
versions, release notes, and artifacts.

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
- The XCTest suite passes, including the magnification regression tests.
- A release app bundle is staged at `dist/Docking.app`.
- A local release-candidate zip is written to `dist/Docking-<version>-macos26.zip`.
- A tester-facing DMG is written to `dist/Docking-<version>-macos26.dmg`.
- Matching checksum files are written for the zip and DMG.
- The zip contains the expected `Docking.app` bundle root, executable,
  `Info.plist`, app icon, and menu bar template icon.
- The DMG contains `Docking.app`, the same required bundle files, and an
  Applications symlink for drag-install testing.
- Both checksum files validate with `shasum -c`.
- Both bundle version values match `APP_VERSION` in `script/release_check.sh`.
- The bundle identifier is `app.docking.docking`.
- The bundle minimum system version is `26.0`.
- Calendar and Location usage descriptions match the reviewed Docking-specific
  permission copy.
- `codesign --verify --deep` accepts the staged app bundle.
- The source hygiene search returns no matches for forbidden availability shims
  or deprecated Calendar permission APIs in `Sources`, `Validation`,
  `Package.swift`, and `script/build_and_run.sh`.
- The user-specific identifier/path search returns no matches across authored
  project files. It intentionally excludes build output, `.git`, and
  `script/release_check.sh` so the check covers app-facing source and docs
  without matching the gate's own pattern definitions.
- `MockWeatherProvider.swift` remains DEBUG-only and the release executable does
  not contain the mock provider implementation.
- The final release identity section prints the current branch, short commit,
  worktree cleanliness, SHA-256 values for the zip and DMG, and both checksum
  file paths.
- The GitHub Actions release-candidate workflow runs the same local release
  gate on a macOS 26 runner, uploads the zip/DMG/checksum set as workflow
  artifacts, attaches the same files to a draft GitHub Release when no published
  release exists, and refuses to mutate assets that were already published from
  a reviewed local candidate.
- The Homebrew cask at `Casks/docking.rb` stays on the latest published DMG
  until the Actions-built release DMG checksum is known. Draft release assets
  can establish that SHA, but `brew audit --cask --strict --online` only works
  after publication, so the clearest operation is to update the cask after the
  release is public.

`./script/build_and_run.sh --verify` remains the quick launch smoke test. The
release gate packages without launching so an artifact inspection does not also
change app windows, permissions, or local user defaults.

Run this after launch, windowing, widget, or SwiftUI/AppKit lifecycle changes:

```bash
./script/launch_smoke_check.sh
```

Expected results:

- `Docking` is still running after the settle window, not just immediately after
  LaunchServices opens the bundle.
- The script prints a short `ps` sample for CPU and RSS.
- The unified log contains no SwiftUI `Publishing changes from within view
  updates` warning for Docking during launch.

Recorded release evidence: passed 2026-07-11 on the `v0.0.4` tag. The Release
Candidate workflow created `Docking-0.0.4-macos26.zip` and
`Docking-0.0.4-macos26.dmg`, uploaded the public release assets, and generated
checksum files that matched the downloaded artifacts. The release zip SHA-256
was `f700d5572b91d87c43d474e6e7ceeee13a5c1e6b92c926d26aff8b8bb8e756cf`; the
release DMG SHA-256 was
`872e1d56a9e8fd973cf46c6f160fa06787c9762487ce5a1148e6603b0be55aed`. The
Homebrew cask checksum matches the Actions-built public DMG.

Previous release evidence: passed 2026-07-05 on the `v0.0.3` tag. The Release
Candidate workflow created `Docking-0.0.3-macos26.zip` and
`Docking-0.0.3-macos26.dmg`, uploaded the public release assets, and generated
checksum files that matched the downloaded artifacts. The release zip SHA-256
was `31683b55cb4df8655f08c22e6160652f4106de8eccdb482aa70f5f35ecc80f4f`; the
release DMG SHA-256 was
`cea82c01faef0c6c7dceb4f10aefb1b81e65f15fc31805f75ee7fc16d3619bf9`. The
Homebrew cask checksum matches the Actions-built public DMG.

Previous Actions evidence: passed 2026-07-05 in PR #8 on the macOS 26 Actions
runner. The run created `dist/Docking-0.0.2-macos26.zip` and
`dist/Docking-0.0.2-macos26.dmg`, verified the staged app signature, verified
the archive contents and checksum files, and confirmed that unprovisioned builds
omit the WeatherKit entitlement so Weather uses the Open-Meteo real-data
fallback instead of failing at launch.

Previous automated evidence: passed 2026-06-30 on the `0.0.1`
release-candidate path. The run created `dist/Docking-0.0.1-macos26.zip` and
`dist/Docking-0.0.1-macos26.dmg`, verified the staged app signature, verified
the archive contents and checksum files, and confirmed that unprovisioned builds
omit the WeatherKit entitlement so Weather uses the Open-Meteo real-data
fallback instead of failing at launch. The generated zip SHA-256 was
`e364bcad70418c634c4afb0adf45702a55c120fbc553eb661fa5569585dcb759`; the
generated DMG SHA-256 was
`c673f3d2cb485b0bbd0f78de3a4546e690720798eec9cd381c55272ce4fe0be8`. The
published Actions-built `v0.0.1` DMG is the cask source of truth and has
SHA-256 `268df87acd3af003befc2c2fd7b15f4e8c3167867fe969969fe340e98da23195`.

Earlier automated evidence: passed 2026-06-29 on the `0.0.0`
release-candidate path. The run created `dist/Docking-0.0.0-macos26.zip` and
`dist/Docking-0.0.0-macos26.dmg`, verified the staged app signature, verified
the archive contents and checksum files, and confirmed that unprovisioned builds
omit the WeatherKit entitlement so Weather uses the Open-Meteo real-data
fallback instead of failing at launch. A launch smoke pass on the same path kept
Docking resident after the settle window, sampled it at 0.0% CPU with roughly
160 MB RSS, and showed no SwiftUI publish-within-update warning in the launch
log.

Previous release evidence: `Release/0.0.0 candidate` was merged on 2026-06-29 as
`bfb50cc`, with the `v0.0.0` tag on `c30222c`. The published GitHub Release
contains the DMG, zip, and matching checksum files. The Homebrew cask points at
the published DMG checksum
`4886c28298ecf1bf47f1118d5b5347bafde7020ec3f5e70f5cee3bc43982918b`, and
`brew audit --cask --strict --online --tap=sk-226/docking docking` passes
against that published artifact.

## Current basic Dock interaction work (2026-09-22)

The work is on branch `feature/native-dock`. The current acceptance scope
is basic Dock operations and interaction feel, with a crowded real-app fixture.
See `NATIVE_DOCK_BEHAVIOR.md` for native references and verification boundaries.
Older dated entries below are historical evidence.

Crowded Tart fixture: 33 pinned apps including Terminal, two
folders and two detailed widgets. Checks performed in a release build:

- Bottom: moved Calculator in both directions and Automator from the tail into
  the middle. Left: moved Calendar downward. Right: moved Calculator upward.
  The persisted list retained all 34 distinct IDs, Finder first and folders last.
- A rapid drag that previously failed to start now commits its final position
  on mouse-up. A 30 second file watch recorded one save for the successful drag.
- Magnification stays available when the resting items fill the display. Screen
  fit is stable across entry/exit, with tests at 32 and 70 items on every edge.
- Show Desktop leaves the dock visible. Dragging and menus hold magnification
  geometry so an in-progress entry animation cannot move insertion targets.
- Mouse-only menu selection through CUA failed for both Docking and Finder's
  native Show View Options menu. This automation route is not a physical-input
  validation. Earlier Docking App Expose keyboard selection is separate evidence.

Final gate: 105 XCTest cases, 60 validation checks, release package inspection
and release launch smoke passed. Host and guest matched on all 107 build inputs.
The pre-renderer checkpoint's 30 second idle sample was 0.0% CPU and stable 142096 KiB RSS.
The new renderer passed release launch smoke at 0.0% CPU / 133856 KiB RSS.
Temporary entry-layout samples improved from roughly 5.6 ms to 3.9 ms; this
is CPU layout work, not native-equivalent frame pacing. The 105-test candidate
retained all 35 IDs after a bottom-edge Calculator reorder. The trace code is
removed. Continuous physical-pointer comparison remains a hands-on check.
Auto-hide hid the populated Dock and Show Docking restored it. Final review
configuration is Bottom / Always visible / Instant with magnification enabled.

Post-review fixes: the updated source passes 108 XCTest cases, all 60 validation
checks and debug launch smoke in Tart. A hidden Dock with magnification disabled
now refreshes folder click coordinates after adding an item and showing it again;
an isolated full-model reproduction reports the actual visible frame. The image
regressions cover Retina pixel dimensions, selection of the high-resolution
representation, and reuse across magnification frames. A live crowded-Dock check
opened a folder and closed it by clicking its source again with magnification on.
Folder/widget dismissal monitors now track subsequent source-frame changes too.
The earlier release ZIP and release measurements above predate these fixes.

Do not infer smooth physical pointer motion, frame-rate guarantees or a full
multi-display test from these checks. Keep the larger fixture when manually
checking fast direction changes, long drags, cancel, outside removal, modifiers
and edge summoning.

## Manual gates and post-release follow-up

| Area | Steps | Pass condition | Status |
| --- | --- | --- | --- |
| First launch | Run `./script/build_and_run.sh --verify`, then open Control Center from the app menu and menu bar item. | Dock panel appears, menu bar item works, Control Center opens without crash. | Passed 2026-06-28 via `--verify` and Computer Use: Overview, app menu, and Control Center opened without crash. |
| Calendar permission not requested while disabled | Turn Calendar widget off, reopen Control Center > Widgets. | No Calendar permission prompt appears. | Passed 2026-06-28 via Computer Use: disabling the Calendar widget kept the Widgets tab stable, disabled the Load button, showed `Enable the Calendar widget to choose calendars.`, and did not show a macOS permission prompt. Validation also covers disabled direct refresh/source load/store-change paths. |
| Calendar permission granted | Turn Calendar widget on and grant Calendar access. | Detail panel shows grouped events or a clear empty state. | Partially covered 2026-06-29 by validation: an authorized provider with events now publishes `loaded`, forwards lookahead/max-event/selected-calendar settings, updates compact/detail copy from the loaded event, and loads selectable calendar sources; an authorized provider with no events publishes the calm empty state. Live macOS TCC grant flow is still not yet manually verified. |
| Calendar permission denied | Deny Calendar access in System Settings, then open the widget. | Detail panel shows a permission state and does not crash. | Partially covered 2026-06-29 by validation: denied authorization publishes `permissionDenied`, restricted publishes `permissionRestricted`, write-only publishes `permissionWriteOnly`, compact text becomes `Off` / `Calendar`, detail/source copy stays permission-specific, and direct refresh/source loading do not crash. Live System Settings denial is still not yet manually verified. |
| Weather manual city | Disable current location, set a city such as `Tokyo`, open Weather. | Real weather loads or a provider/network error is shown with no mock values. | Passed 2026-06-28 via Computer Use: manual city `Tokyo` showed real weather for `Tokyo, Tokyo, Japan`, updated at 19:05, with temperature, condition, hourly/daily forecast, and humidity. Missing manual city with cached data now shows a stale-cache message instead of a contradictory bare city prompt. |
| Weather location denial | Enable current location and deny Location Services. | Weather shows the location-denied state and does not silently fall back to fake data. | Partially covered 2026-06-28 by validation: current-location denial with no manual fallback publishes `locationDenied` and no fabricated snapshot; with cached weather it shows stale cached data; with a manual city it falls back to the configured city. Live Location Services denial is still not yet manually verified. |
| App launcher and process actions | Add an `.app`, launch it from Docking, Command-click it, right-click it, use Show All Windows and Hide, use Quit, Option-open the menu for Force Quit, drop a document onto the app icon, remove it, reset the list. | Icon loads once, normal click opens through `NSWorkspace`, Command-click reveals the app in Finder, document drops open through that app instead of adding arbitrary files to Docking, running indicator updates, Show All Windows enters native App Exposé for that app, Hide hides it, Quit requests graceful termination for the selected Dock tile scope, Force Quit replaces Quit instead of appearing beside it, and Docking-specific actions live under the Docking submenu. | Passed 2026-06-28 via Computer Use and validation: previous Computer Use confirmed Open, Show All Windows, Hide, Quit, Finder reveal, removal, Force Quit confirmation, and disposable DockingProbe termination. Current validation covers normal `Quit` vs Option-modified `Force Quit...` as mutually exclusive menu titles, per-Dock-tile Quit/Force Quit targeting for duplicate app instances, grouped single-tile app termination, quit-pending menu state, and ignoring app-specific Dock extras such as complete-quit commands. Live context-menu inspection showed `Open`, `Show All Windows`, `Hide`, `Quit`, `Options > Keep in Docking / Show in Finder`, and `Docking > Open Control Center`. Command-click reveal and document-drop-to-app behavior are implemented but still need live UI verification. |
| Folder stacks | Add a folder from the picker or Finder drop, click it, right-click it, change Sort By, Display as, and View content as. Use Primary Dock match on a Dock with Applications/Downloads folders. Right-click and drag an item from an open stack. Drop a temporary file onto a Dock folder icon. | Folder click opens a stack panel anchored to the folder icon; clicking the same icon closes it; Open opens Finder; Sort By/Display as/View content as affect the item; Remove from Docking never deletes the folder; Primary Dock match imports `persistent-others`; Downloads initially shows 12 visible items, loads more while scrolling, and updates the header count as the user scrolls back up/down; stack entries expose Open/Show in Finder and drag their real file URL to other Mac apps; folder icon drops copy/move into the real folder using Finder-style same-volume/Option semantics. | Partially covered 2026-06-29 by validation and screenshot review: Apple Dock mirroring imports `persistent-others` directory tiles with `displayas`/`showas`/`arrangement`; app catalog accepts folders (the 2026-09-21 update additionally accepts documents); folder stack sorting and Automatic/Fan/Grid/List presentation resolve correctly; Downloads recent sorting keeps a 12-item initial page and full older list for scroll reveal; generated Dock icons use the full Retina backing so the Downloads icon stays centered and app-sized; Downloads header range updates back to `1-12` when scrolled to the top of loaded entries and advances to `25-36` lower in the loaded grid; Downloads page reveal now uses scroll geometry rather than requiring SwiftUI `ScrollPhase`, so trackpad/wheel inertia in the non-activating stack panel is less likely to miss additional pages. Stack entry context menus, file-url drag providers, and folder-drop file operations are implemented, but live Finder drag/drop is still not yet manually verified. |
| Unpinned running apps | Launch an app that is not kept in Docking, such as Zed, then toggle Control Center > General > Unpinned running apps. | The running app appears once in a separated section when enabled and disappears when hidden; pinned apps are not duplicated. | Passed 2026-06-28 via Computer Use: Overview showed 5 running unpinned apps; General showed `Show separated`; Dock AX tree showed Zed once in the transient section. |
| Appearance and magnification | Adjust Dock size, widget size, and magnification in Appearance. Test minimum/maximum sizes and bottom/left/right placement. Open a widget and the add picker. | Icons and the panel share dimensions; widgets do not increase Dock thickness; nearby icons expand without overlapping; the small add button stays clickable. | Partially verified 2026-09-21 in Tart (macOS 26.6.2, Swift 6.2.3): the earlier native arithmetic snapshot passed all 73 XCTest cases, all 60 validation checks, and launch smoke. Live checks covered bottom/left/right placement and activation through the enlarged icon outside the glass. Native coordinate-warp and timing fixtures, gap accounting, pointer targeting, bounds and animation settlement are automated. Earlier slider/widget/add-picker checks and frame-cadence measurements are historical, not rerun evidence for this curve. Full native motion parity, multi-display, full-screen, auto-hide interaction and accessibility preference changes remain unverified. See NATIVE_MAGNIFICATION.md and MAGNIFICATION_HANDOFF.md. |
| Dock accessibility | Show the Dock and inspect the accessibility tree. | Each dock item exposes its own name, running/folder state, and button role; the dock group label does not replace child labels. | Passed 2026-06-28 via Computer Use: dock items reported `button` with app-specific descriptions such as Finder, Zed, Calendar, Weather, and the add item control. |
| Widget panel toggle | Open Calendar or Weather from Docking's Dock, then click the same widget again. | Detail panel opens without crashing; clicking the same widget closes it; Dock remains reachable while the panel is open. | Passed 2026-06-28: Computer Use confirmed the Weather detail panel opens through the same model action, and the user verified that clicking the widget again closes the panel. Validation covers same-click retoggle suppression so outside-click dismissal cannot immediately reopen the same widget. |
| Reorder/drop | Reorder items inside the dock and drop an external `.app` or folder. | Ordering persists; app bundles become application items; folders become folder stack items; plain files become document shortcuts after applications; Finder stays first. | Partially passed 2026-06-29 via Computer Use and validation: Items tab reorder still uses explicit up/down controls; validation covers `.app` bundle drops preserving app metadata, folder drops creating stack items, and plain file drops creating document items (updated 2026-09-21). The 2026-09-21 AppKit layer also reordered Photos inside Docking in Tart and persisted the new order. Timed drag removal and Finder-to-Docking drag/drop remain unverified. |
| Auto-hide | Enable Auto-hide. Touch the physical edge and stop, then try again while continuing to push outward after contact. Repeat every Edge response preset, all Dock edges, and a full-screen app. | Mere contact or a long stationary dwell does not reveal. A deliberate outward push followed by the configured delay does; leaving the edge cancels it. Full-screen-like bottom edges still require two deliberate pushes. Normal hide delay and explicit Show Dock remain unchanged. | New intent logic is covered by DockEdgeIntentTests. Physical mouse/trackpad behavior, timing and native parity remain unverified; earlier dwell-only evidence does not validate this gesture. |
| Edge input passthrough | In both visibility modes, place another app's controls at the bottom edge, including 0-1 pt and 4-8 pt above it. Click, right-click, drag a scrollbar, scroll, and slide sideways; repeat while a reveal is pending, over Docking windows, and on a noncurrent display. | Underlying controls receive input. None of these operations arms a reveal or a full-screen second push; any pending reveal is canceled. One continuous push reveals at most once. | DockEdgeInputTests checks click-through panels and monitor event coverage; DockEdgeIntentTests covers intent cancellation and consumption. Actual event delivery and absence of input loss need live macOS verification. |
| Explicit Show Dock in auto-hide | Enable auto-hide, press Show Dock, close Control Center, and wait beyond the configured delay. | A stale auto-hide task must not immediately hide a dock the user explicitly asked to show. | Passed 2026-06-28 via Computer Use: pressing Show Dock in auto-hide mode, closing Control Center, and waiting beyond the 0.7s delay left the Docking Dock visible and accessible. |
| Keep above windows | Toggle Control Center > General > Keep above other windows off and on. | Docking uses ordinary window level when off and floating dock level when on, without stealing focus. | Passed 2026-06-28 via Computer Use and validation: General toggle changed OFF and back ON without crashing or moving settings; `DockPanelController.windowLevel(for:)` validates `.normal` when off and `.floating` when on while the panel remains non-activating. |
| Spaces/full-screen | Toggle all-Spaces/full-screen settings and move through Spaces/full-screen apps. | Dock remains available without stealing focus. | Partially covered 2026-06-28 by validation: dock and edge-trigger panels share the same transient/ignores-cycle collection behavior; default settings include all-Spaces and full-screen auxiliary flags, and turning the toggles off removes those flags. Live Space/full-screen movement is still not yet manually verified. |
| Multiple displays | Test Automatic and Fixed display with Auto-hide and Always visible. With separate Spaces enabled, cross displays without touching an edge, then deliberately push at another bottom edge. Change a fixed target during a pending reveal; disconnect/reconnect it. Repeat with separate Spaces disabled and all bottom alignments. | Crossing alone never moves the Dock. Automatic bottom summoning works in both visibility modes only with separate Spaces. Fixed selection always wins; disconnect falls back to primary. Fixed returns on reconnection; Automatic stays at its fallback until summoned. Icon/size updates preserve placement. | Selection rules are covered by DockDisplayPolicyTests. Live multi-monitor, stacked/overlapping layouts, and side-edge native comparison remain unverified. See DISPLAY_PLACEMENT.md. |
| Sleep/wake | Put the Mac to sleep and wake it with Docking running. | Dock repositions, running app state refreshes, widgets remain responsive. | Partially covered 2026-06-28 by implementation review: Docking observes `NSWorkspace.didWakeNotification`, reapplies window settings, refreshes the running-app snapshot once, and calls calendar/weather `refreshIfNeeded`. Actual machine sleep/wake is still not yet manually verified. |
| Restore safety | Open Control Center > Restore, inspect primary mode, match-original-layout, restore, disable, and reload controls. Do not confirm reload unless intentionally testing Apple Dock restart. | Primary mode explains snapshot/restore behavior; match-original-layout imports readable Apple Dock layout into Docking; enable, disable, restore, and reload all show confirmation before changing Apple Dock preferences or restarting Dock; restore/disable do not crash. | Partially passed 2026-06-29 via implementation review and Computer Use: Restore displayed snapshot time, restore/manual instructions, reload button, and Quit; dangerous Apple Dock actions now use confirmation dialogs. `killall Dock` confirmation/reload was not executed. |
| Idle performance | Leave pointer away from the dock for several minutes in Activity Monitor. | CPU stays close to 0% and memory remains stable. | Partially covered by short `ps` sampling of the live `Docking` process. 2026-06-29 sample after `./script/build_and_run.sh --verify`: startup-adjacent CPU was 1.3% with RSS 165,536 KB, then settled to 0.0% CPU with RSS about 158,900 KB across a 30-second idle window. Longer Activity Monitor observation is still not yet manually verified. |
| Network cadence | Open Weather once and observe logs/network. | Refreshes do not repeat every few seconds. | Partially covered 2026-06-28 by validation: fresh cached weather suppresses passive `refreshIfNeeded` and non-forced refresh provider calls, while forced manual refresh still works. Live log/network observation is still not yet manually verified. |

## Git/GitHub readiness

GitHub handoff for `0.0.0` is complete:

- PR #1 was merged into `main`.
- The release tag is reachable from `origin/main`.
- The GitHub Release includes DMG/zip artifacts and checksum files.
- The Homebrew cask audits successfully against the published DMG.

Do not mark the broader product goal fully complete until the remaining
partially covered target-machine checks in the table above are either passed on
the user's machine or deliberately accepted as known limitations:

- Live macOS Calendar grant and denial flows.
- Live Location Services denial flow.
- Finder-to-Docking drag/drop for apps, folders, documents, and stack entries.
- Physical pointer-edge auto-hide reveal.
- Live Spaces/full-screen and multi-display movement.
- Actual sleep/wake behavior.
- Longer Activity Monitor idle CPU/memory observation.
- Live network cadence observation after opening Weather.

For future release handoffs, start only after:

- All automated gates pass on the current worktree.
- Manual gates above are either passed or deliberately recorded in `QA.md`,
  release notes, or a milestone issue. Keep `README.md` limited to user-facing
  installation and usage facts.
- The worktree has no unrelated local changes mixed into the app milestone.
- The branch/commit message states that this is a pre-release native
  macOS app and that Apple Dock preferences remain overlay-only until the user
  explicitly enables primary dock mode.
