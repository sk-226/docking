# Docking

`Docking` is a native macOS overlay dock built with SwiftUI and a narrow AppKit
windowing layer. It is a personal Dock-style app inspired by the product goals in
the attached goal document, but it does not copy Dockspace code, assets, icons,
text, or layout.

## Current 0.0.0 App

- Translucent dock panel using `NSPanel`, with bottom center, bottom left,
  bottom right, left, and right placement options.
- App icons launch through `NSWorkspace`; folder items open Docking stack
  panels and can also be opened in Finder.
- Running and active app indicators update from `NSWorkspace` notifications, not
  polling.
- App/folder add by picker or drag/drop, remove, reset, Finder reveal, context
  menus with app process actions and folder stack options, Dock drag reorder,
  and explicit Control Center reorder buttons.
- Downloads is treated as a recent stack: its panel opens with 12 visible items
  and loads more as the user scrolls, while its dock icon stays recognizable as
  Downloads instead of trying to draw the whole folder.
- Dock app-control parity is tracked in [DOCK_PARITY.md](DOCK_PARITY.md),
  including implemented Quit, Force Quit, Hide, Show All Windows, and folder
  stack behavior.
- Running apps that are not kept in Docking can appear in a separated transient
  section, or be hidden entirely from Control Center.
- Calendar widget backed by EventKit with loading, denied, empty, loaded, and
  error states. Calendar sources can be selected in Control Center; an empty selection
  intentionally means all calendars.
- Weather widget with a provider abstraction, WeatherKit-first provider,
  Open-Meteo fallback/manual-city provider, and CoreLocation-based
  current-location flow. It does not show fake production weather. Preview/test
  mock data is compiled only in `DEBUG`. Open-Meteo weather can also show Air
  Quality when the public air-quality endpoint returns a current AQI value.
- Single Control Center window for dock sizing, dock position, auto-hide,
  unpinned running-app visibility, keep-above behavior, widgets, weather
  location/unit, calendar lookahead, display choice, accent color, material
  strength, launch at login, and restore messaging.
- Control Center has selectable General, Appearance, Items, Widgets, and Restore
  sections.
- Menu bar status item with show, hide, Control Center, widget, and quit
  actions; it can be hidden from Control Center.
- Keyboard commands:
  - `Command-Shift-D`: show Docking
  - `Command-Option-C`: open Calendar widget
  - `Command-Option-W`: open Weather widget
- Restore section that clearly states this 0.0.0 app is overlay-only and does
  not alter Apple Dock settings by default.
- Primary Dock mode imports readable Apple Dock layout details, pinned apps, and
  folder stacks into Docking before moving Apple Dock out of the way.

## Build

```bash
swift build
```

For the app product specifically:

```bash
swift build --product Docking
```

## Validate

This environment does not expose `XCTest`/`Testing`, so the repository includes a
small framework-free validation executable that exercises the key pure logic:

```bash
swift run DockingValidation
```

It checks formatter output, calendar grouping, dock sizing, widget detail-panel
anchoring math, specific-display placement, Apple Dock app/folder mirroring,
folder stack sorting/presentation, settings persistence, accent color option
coverage, weather cache freshness/round-trip, WeatherKit-to-Open-Meteo fallback
boundaries, and restore snapshot serialization.

Use [QA.md](QA.md) for the manual gates
that cannot be proven by SwiftPM alone, including real Calendar/Location
permission flows, Spaces, multiple displays, sleep/wake, and Activity Monitor
checks. Use [PERFORMANCE.md](PERFORMANCE.md) for the dedicated idle CPU,
memory, network-cadence, and sleep/wake performance pass.

## Run

The project includes a local app-bundle run script so the SwiftPM GUI target
launches like a normal macOS app:

```bash
./script/build_and_run.sh
```

Useful modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
CONFIGURATION=release ./script/build_and_run.sh --package
```

For launch-only regression checks that should not be part of artifact
packaging, run:

```bash
./script/launch_smoke_check.sh
```

That script relaunches Docking, waits for the resident app to settle, confirms
the process is still alive, and fails if the launch logs contain the SwiftUI
publish-within-view-update warning that previously broke the first Control
Center render.

The Codex app Run action is wired to the same script through
`.codex/environments/environment.toml`.

## Icons

The app icon and menu bar template icon follow the selected "minimal rocket over
translucent dock shelf" direction. Regenerate them after icon design changes:

```bash
./script/render_icons.swift
```

The generated resources live in `Resources/` and are copied into the staged app
bundle by `./script/build_and_run.sh`.

## Release Candidate

Run the local release gate before sharing a build:

```bash
./script/release_check.sh
```

It runs the validation executable, builds and stages a release `Docking.app`,
checks bundle metadata, Calendar/Location permission descriptions, icon
resources, signature integrity, and WeatherKit entitlement/profile consistency,
rejects user-specific authored paths/identifiers, verifies that the debug mock
weather provider is not in the release executable, and writes
`dist/Docking-0.0.0-macos26.zip` plus
`dist/Docking-0.0.0-macos26.zip.sha256`. It also prints the current branch,
commit, worktree cleanliness, and package SHA-256 so the tested zip can be tied
back to the exact local candidate. This is a local 0.0.0 candidate gate;
Developer ID signing, hardened runtime, notarization, and GitHub push remain
separate explicit release steps.

Run the launch smoke check after changes that touch startup, windows, widgets,
or AppKit/SwiftUI lifecycle:

```bash
./script/launch_smoke_check.sh
```

This intentionally stays separate from `release_check.sh`. The release gate
inspects a packaged artifact without mutating local app state; the smoke check
launches Docking, waits for it to remain resident, prints a short CPU/RSS sample,
and fails if SwiftUI logs the publish-within-update warning that can leave the
Control Center blank during first launch.

## Permissions

Calendar data is read locally through EventKit. macOS will ask for Calendar
permission the first time the calendar widget loads. If permission is denied,
the widget shows a clear permission state instead of crashing or hiding the
problem.

Weather can use either a manual city or current location:

- WeatherKit is tried first when it can resolve a location.
- Manual city can fall back to Open-Meteo geocoding and forecast APIs.
- Current location asks CoreLocation for a one-shot coarse location, then uses
  that coordinate with WeatherKit or Open-Meteo forecast data.
- If current location is unavailable and a manual city is set, Docking retries
  with that manual city instead of leaving the widget stuck on a location error.
- WeatherKit requires a provisioning profile that grants
  `com.apple.developer.weatherkit` for `app.docking.docking`. The run script
  attaches that entitlement only when it detects a matching profile, or when
  `DOCKING_WEATHERKIT_PROFILE` points at one. Otherwise Docking launches without
  the restricted entitlement and falls back to Open-Meteo.

## Primary Dock Mode and Restore

Docking's own dock is the main product surface. By default it stays safe and
overlay-only:

- `Docking` does not hide the standard macOS Dock.
- `Docking` does not run `killall Dock`.
- `Docking` does not modify `com.apple.dock` preferences in the current
  overlay-only mode.

Use Control Center > Restore > **Use Docking as Primary Dock** when you explicitly
want Docking to take over day-to-day dock behavior. That action saves the
current Apple Dock preferences, mirrors the readable original Dock layout,
pinned apps, and folder stacks into Docking, then changes Apple Dock to strong
auto-hide settings. Use **Match Original Apple Dock Layout** if primary mode was
already enabled and you want to re-import the saved layout. Use **Restore
Original macOS Dock Settings** or **Disable Primary Mode** to write the saved
settings back after confirmation. The automatic restore path verifies the
readable Dock preference values after writing them; if verification fails, the
Restore section keeps the manual Terminal commands visible.

The Restore section also includes **Reload Apple Dock to Apply**. That button is
separate because it runs `killall Dock`; Docking only does this after the user
confirms the dialog. Reloading Apple Dock only applies Apple Dock preference
writes; Docking's own reproduced layout is controlled by the match/import action
above.

## Privacy

- Calendar events stay local.
- App usage is not uploaded.
- There is no analytics code.
- Weather manual-city lookups call Open-Meteo only when the Weather widget is
  enabled and a manual city is configured.

## Known Limitations

- WeatherKit is wired as the primary provider, but builds without a matching
  WeatherKit provisioning profile are expected to fall back to Open-Meteo.
- Launch at login uses `SMAppService.mainApp`. It may fail for unsigned or
  nonstandard development bundles; Control Center keeps the checkbox synced to
  macOS's actual Login Items state and shows the error.
- Widget detail panels use reported widget screen frames when available, with a
  dock-centered fallback during early layout.
- Placement display supports "Main display", "Follow pointer", and a chosen
  connected display by `NSScreen` display ID. Bottom auto-hide still reveals
  from every display edge; this setting controls the default anchor and
  non-bottom placement. If a chosen display disappears, Docking falls back to the
  main display.
- Full-screen Spaces and multi-display behavior use conservative panel
  collection behavior and still need manual QA on the target machine.
- Before a wider GitHub/public handoff, the remaining target-machine checks in
  [QA.md](QA.md) should be completed or consciously accepted: granted/denied
  Calendar permission flows, Location Services denial, live Finder drag/drop
  into and out of folder stacks, physical pointer-edge auto-hide reveal, actual
  sleep/wake, longer Activity Monitor idle sampling, and network-cadence
  observation after opening Weather.
