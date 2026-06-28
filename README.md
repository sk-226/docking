# Docking

`Docking` is a native macOS overlay dock built with SwiftUI and a narrow AppKit
windowing layer. It is a personal Dock-style app inspired by the product goals in
`/Users/sugu/Downloads/docking.md`, but it does not copy Dockspace code, assets,
icons, text, or layout.

## Current 0.0.0 App

- Translucent dock panel using `NSPanel`, with bottom center, bottom left,
  bottom right, left, and right placement options.
- App icons launch through `NSWorkspace`.
- Running and active app indicators update from `NSWorkspace` notifications, not
  polling.
- App add by picker or `.app` drag/drop, remove, reset, Finder reveal, context
  menu with Quit/Force Quit for running apps, Dock drag reorder, and explicit
  Control Center reorder buttons.
- Dock app-control parity is tracked in [DOCK_PARITY.md](DOCK_PARITY.md),
  including implemented Quit, Force Quit, Hide, and Show All Windows behavior.
- Running apps that are not kept in Docking can appear in a separated transient
  section, or be hidden entirely from Control Center.
- Calendar widget backed by EventKit with loading, denied, empty, loaded, and
  error states. Calendar sources can be selected in Control Center; an empty selection
  intentionally means all calendars.
- Weather widget with a provider abstraction, WeatherKit-first provider,
  Open-Meteo fallback/manual-city provider, and CoreLocation-based
  current-location flow. It does not show fake production weather. Preview/test
  mock data is compiled only in `DEBUG`.
- Single Control Center window for dock sizing, dock position, auto-hide,
  unpinned running-app visibility, keep-above behavior, widgets, weather
  location/unit, calendar lookahead, display choice, accent color, material
  strength, launch at login, and restore messaging.
- Control Center has selectable General, Appearance, Apps, Widgets, and Restore
  sections.
- Menu bar status item with show, hide, Control Center, widget, and quit
  actions; it can be hidden from Control Center.
- Keyboard commands:
  - `Command-Shift-D`: show Docking
  - `Command-Option-C`: open Calendar widget
  - `Command-Option-W`: open Weather widget
- Restore section that clearly states this 0.0.0 app is overlay-only and does
  not alter Apple Dock settings by default.
- Primary Dock mode imports readable Apple Dock layout details and pinned apps
  into Docking before moving Apple Dock out of the way.

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
anchoring math, specific-display placement, settings persistence, accent color
option coverage, weather cache freshness/round-trip, WeatherKit-to-Open-Meteo
fallback boundaries, and restore snapshot serialization.

Use [QA.md](QA.md) for the manual gates
that cannot be proven by SwiftPM alone, including real Calendar/Location
permission flows, Spaces, multiple displays, sleep/wake, and Activity Monitor
checks.

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
```

The Codex app Run action is wired to the same script through
`.codex/environments/environment.toml`.

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
- WeatherKit requires the appropriate Apple entitlement in real distribution.
  Unsigned SwiftPM bundles usually fall back to Open-Meteo.

## Primary Dock Mode and Restore

Docking's own dock is the main product surface. By default it stays safe and
overlay-only:

- `Docking` does not hide the standard macOS Dock.
- `Docking` does not run `killall Dock`.
- `Docking` does not modify `com.apple.dock` preferences in the current
  overlay-only mode.

Use Control Center > Restore > **Use Docking as Primary Dock** when you explicitly
want Docking to take over day-to-day dock behavior. That action saves the
current Apple Dock preferences, mirrors the readable original Dock layout and
pinned apps into Docking, then changes Apple Dock to strong auto-hide settings.
Use **Match Original Apple Dock Layout** if primary mode was already enabled and
you want to re-import the saved layout. Use **Restore Original macOS Dock
Settings** or **Disable Primary Mode** to write the saved settings back. The
automatic restore path verifies the readable Dock preference values after
writing them; if verification fails, the Restore section keeps the manual
Terminal commands visible.

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

- WeatherKit is wired as the primary provider, but unsigned or non-entitled
  SwiftPM bundles are expected to fall back to Open-Meteo.
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
