# Development

This file keeps maintainer-facing notes out of the user-facing README.

## Run Locally

Use the app-bundle script for GUI work:

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

The script stages a real `.app` bundle because a SwiftPM executable launch does
not exercise the same Info.plist, resource, permission-description, and signing
paths that users run.

## Validation

Run pure-logic validation with:

```bash
swift run DockingValidation
```

Use a scratch path if the local SwiftPM build database is stale or failing:

```bash
swift run --scratch-path /private/tmp/docking-validation DockingValidation
```

Run the launch smoke check after startup, window, widget, AppKit, or SwiftUI
lifecycle changes:

```bash
./script/launch_smoke_check.sh
```

The smoke check launches Docking and watches for first-render failures that a
packaging-only release check cannot detect.

## Release Candidate

Before sharing a build, run:

```bash
./script/release_check.sh
```

The release gate builds the release app bundle and verifies bundle metadata,
permission usage descriptions, icon resources, local signature integrity,
WeatherKit entitlement/profile consistency, source hygiene, release-only mock
boundaries, and generated zip/DMG artifacts.

This is not a notarization gate. Developer ID signing, hardened runtime,
notarization, GitHub release publication, and Homebrew cask updates should stay
explicit release steps so a local pre-release candidate is not mistaken for a fully
notarized public build.

## WeatherKit

WeatherKit requires a provisioning profile that grants
`com.apple.developer.weatherkit` for `app.docking.docking`.

`script/build_and_run.sh` attaches that entitlement only when it detects a
matching profile, or when `DOCKING_WEATHERKIT_PROFILE` points at one. Without
that profile, Docking should launch without the restricted entitlement and use
the Open-Meteo fallback instead.

## Icons

Regenerate icon resources after icon design changes:

```bash
./script/render_icons.swift
```

Generated resources live in `Resources/` and are copied into the staged app
bundle by `script/build_and_run.sh`.

## Manual QA

Use [QA.md](QA.md) for permission flows, Spaces, multiple displays,
drag-and-drop, sleep/wake, and other checks that need a real macOS session.
Use [PERFORMANCE.md](PERFORMANCE.md) for idle CPU, memory, network cadence, and
sleep/wake performance checks.

## Future Ideas

Unimplemented product ideas live in [FEATURE_IDEAS.md](FEATURE_IDEAS.md).
