# Performance Notes

`Docking` is a resident UI, so the 0.0.0 app favors event-driven updates and
bounded refresh work over constant polling.

## Design Choices

- Running apps are observed with `NSWorkspace` launch, terminate, and activate
  notifications. The app does one initial scan and then reacts to system events.
- App icons are cached by bundle identifier or app path. SwiftUI body refreshes
  reuse decoded `NSImage` instances instead of decoding icons every frame.
- Auto-hide uses a small edge trigger panel with an AppKit tracking area. This is
  intentionally chosen over high-frequency mouse-position polling.
- Calendar refresh happens on launch, panel open, EventKit store change, or after
  a conservative stale interval.
- Weather refresh uses the configured interval, defaulting to 45 minutes. Failed
  refreshes show cached data as stale when a previous snapshot exists.
- Control Center changes update the live dock immediately, but persistence is
  debounced so slider drags do not create a burst of UserDefaults writes.
- Current-location weather uses a one-shot coarse CoreLocation request. It does
  not subscribe to continuous location updates because a dock weather widget only
  needs a forecast-scale coordinate.
- WeatherKit is tried before Open-Meteo, but a missing WeatherKit entitlement is
  treated as a provider failure and falls back to Open-Meteo. The fallback still
  uses real forecast data, not mock values.
- Detail panels are lazy: calendar and weather fetches are triggered when the
  widget/panel needs data.
- Disabling a widget cancels its in-flight refresh and closes its detail panel,
  so disabled widgets do not keep doing background work.
- Reduced Motion disables panel frame animation and hover magnification. This is
  both an accessibility requirement and a small guard against unnecessary motion
  work on machines where users have opted out of animation.
- Material strength uses native SwiftUI material plus lightweight neutral/accent
  overlays. It intentionally avoids private blur APIs so the dock stays
  maintainable and grounded in public macOS APIs.
- Apple Dock preferences are not modified by default, avoiding visible system
  restarts or preference churn.

## Manual Checks

Build and launch:

```bash
./script/build_and_run.sh --verify
```

Check idle CPU and memory:

1. Open Activity Monitor.
2. Search for `Docking`.
3. Leave the pointer away from the dock for several minutes.
4. CPU should be close to 0% while idle; memory should remain stable.

Check network refresh behavior:

1. Set a manual weather city.
2. Open the Weather widget once.
3. Watch network activity or logs.
4. Confirm refreshes do not repeat every few seconds.

Check sleep/wake:

1. Launch `Docking`.
2. Put the Mac to sleep and wake it.
3. Confirm the dock panel is still responsive.
4. Open Calendar and Weather panels once to refresh stale data.

Check Spaces/full-screen behavior:

1. Enable "Show on all Spaces" and "Show on full-screen spaces".
2. Move between Spaces and a full-screen app.
3. Confirm the panel appears without stealing focus.

Check display mode:

1. In Control Center > General, switch Placement display between "Main display"
   and "Follow pointer".
2. Move the pointer to another display and show the dock.
3. Confirm the panel is placed on the selected display mode.
4. If more than one display is connected, select "Chosen display" and choose a
   display from the list.
5. Disconnect that display and confirm Docking falls back to the main display.

Check calendar source selection:

1. Grant Calendar access.
2. Open Control Center > Widgets.
3. Select only one calendar and open the Calendar widget.
4. Confirm events from other calendars are hidden.
5. Press "All" and confirm events from all calendars can appear again.

## Trade-offs

- The 0.0.0 app uses a translucent material panel with a small footprint. A
  larger always-on blur window was avoided because transparent material over a
  large area can become an idle rendering cost.
- Current-location weather is not simulated. Fake data would make the UI look
  complete while hiding the real permission/provider work still needed.
- `killall Dock` is not used after restore writes. Restarting Apple's Dock is a
  disruptive operation and should require a separate explicit confirmation.
