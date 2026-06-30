# Performance Notes

`Docking` is a resident UI, so the pre-1.0 app treats idle cost as a product
requirement. Prefer event-driven updates, cached data, and bounded refresh work
over constant polling or visual effects that keep redrawing while the user is
not interacting with the dock.

## Targets

- Idle CPU should sit close to 0%, ideally below 1% after the dock settles.
- Memory should stay reasonably stable. Current smoke evidence is around
  160 MB RSS, so continuous growth is the release risk to investigate rather
  than a hard 150 MB cap.
- Calendar and Weather refreshes should be event-driven or conservative, not
  repeated every few seconds.
- Settings changes should not write continuously while sliders or segmented
  controls are being adjusted.
- Auto-hide should rely on edge trigger windows and scheduled hides, not a
  continuous mouse-position polling loop.

## Design Choices

- Running apps are observed with `NSWorkspace` launch, terminate, and activate
  notifications. The app does one initial scan and then reacts to system events.
- App icons are cached by bundle identifier or app path. SwiftUI body refreshes
  reuse decoded `NSImage` instances instead of decoding icons every frame.
- Auto-hide uses small edge trigger panels with AppKit tracking areas and a
  bounded hide delay. This is intentionally chosen over high-frequency mouse
  polling because Docking may run all day.
- Calendar refresh happens on launch, panel open, EventKit store change, or
  after a conservative stale interval.
- Weather refresh uses the configured interval, defaulting to 45 minutes. Failed
  refreshes show cached data as stale when a previous snapshot exists.
- Control Center changes update the live dock immediately, but persistence is
  debounced so slider drags do not create a burst of `UserDefaults` writes.
- Current-location weather uses a one-shot coarse CoreLocation request. It does
  not subscribe to continuous location updates because a dock weather widget only
  needs a forecast-scale coordinate.
- WeatherKit is tried before Open-Meteo, but a missing WeatherKit entitlement is
  treated as a provider failure and falls back to Open-Meteo. The fallback still
  uses real forecast data, not mock values.
- Open-Meteo Air Quality is fetched from the separate air-quality endpoint only
  during a normal weather refresh. If that optional request fails, Docking hides
  the AQI row instead of retrying in a loop or failing the whole forecast.
- Detail panels are lazy: calendar and weather fetches are triggered when the
  widget or panel needs data.
- Disabling a widget cancels its in-flight refresh and closes its detail panel,
  so disabled widgets do not keep doing background work.
- Reduced Motion disables panel frame animation and hover magnification. This is
  both an accessibility requirement and a guard against unnecessary motion work
  on machines where users have opted out of animation.
- Material strength uses native SwiftUI material plus lightweight neutral and
  accent overlays. It intentionally avoids private blur APIs so the dock stays
  maintainable and grounded in public macOS APIs.
- Apple Dock preferences are not modified by default, avoiding visible system
  restarts or preference churn.

## Fast Local Sample

Run the app bundle first:

```bash
./script/build_and_run.sh --verify
```

Then sample the live process for at least 30 seconds while the pointer is away
from the Docking dock:

```bash
pid=$(pgrep -x Docking)
ps -o pid,%cpu,rss,etime,command -p "$pid"
sleep 10
ps -o pid,%cpu,rss,etime,command -p "$pid"
sleep 20
ps -o pid,%cpu,rss,etime,command -p "$pid"
```

This is only a smoke check. If CPU is visibly active while idle, inspect recent
changes before relying on a longer Activity Monitor pass.

## Activity Monitor Pass

1. Launch Docking with `./script/build_and_run.sh --verify`.
2. Leave Control Center closed and keep the pointer away from the dock for five
   minutes.
3. Open Activity Monitor and filter for `Docking`.
4. Check CPU and memory in the CPU and Memory tabs.
5. Open the Calendar and Weather widgets once, close them, then wait another
   five minutes.
6. Confirm CPU returns to idle and memory does not climb continuously.

Record the date, app commit, CPU range, and memory range in `QA.md` when this is
done on the target machine.

## Network Cadence

Weather refreshes are allowed on launch, widget open, relevant settings changes,
and manual refresh. They should not repeat every few seconds.

Manual check:

1. Set a manual city in Control Center > Widgets.
2. Open the Weather widget once.
3. Wait at least five minutes without pressing refresh.
4. Use Activity Monitor's Network tab or the unified logs from
   `./script/build_and_run.sh --logs` to confirm there is no tight refresh loop.

The expected behavior is one forecast request when data is missing or stale, then
cached data until the configured refresh interval or a manual refresh.

## Sleep and Wake

1. Start Docking and note the dock position.
2. Put the Mac to sleep.
3. Wake the Mac and unlock it.
4. Confirm the dock is still inside the visible screen area.
5. Confirm running app indicators refresh within a few seconds.
6. Open Calendar and Weather widgets and confirm they stay responsive.

Docking intentionally performs a single post-wake reapply/refresh pass. It
should not start a repeating recovery loop after wake.

## Spaces and Displays

1. Enable "Show on all Spaces" and "Show on full-screen spaces".
2. Move between Spaces and a full-screen app.
3. Confirm the panel appears without stealing focus.
4. In Control Center > General, switch Placement display between "Main display"
   and "Follow pointer".
5. If more than one display is connected, choose a specific display.
6. Disconnect that display and confirm Docking falls back to the main display.

These checks matter because a dock panel can look cheap if it drifts outside the
visible frame or steals focus while the user changes Spaces.

## Calendar Source Selection

1. Grant Calendar access.
2. Open Control Center > Widgets.
3. Select only one calendar and open the Calendar widget.
4. Confirm events from other calendars are hidden.
5. Press "All" and confirm events from all calendars can appear again.

This validates both privacy and performance: Docking should query only the event
window it needs and should not store more calendar data than the panel displays.

## Trade-Offs

- The pre-1.0 app uses a translucent material panel with a small footprint. A
  larger always-on blur window was avoided because transparent material over a
  large area can become an idle rendering cost.
- Current-location weather is not simulated. Fake data would make the UI look
  complete while hiding the real permission/provider work still needed.
- `killall Dock` is isolated behind an explicit Restore action. Restarting
  Apple's Dock is disruptive and should never happen as a side effect of normal
  performance or appearance checks.
