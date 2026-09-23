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
- Edge summoning and Auto-hide should use event monitors and one-shot delays,
  not a continuous mouse-position polling loop.

## Design Choices

- Running apps are observed with `NSWorkspace` launch, terminate, and activate
  notifications. The app does one initial scan and then reacts to system events.
- App icons are cached by bundle identifier or app path. The AppKit interaction
  view retains each icon's decoded layer contents across magnification frames.
  It renders the configured maximum icon size at the window's backing scale,
  rebuilding only when the source image changes or more pixels are needed.
  Resizing updates geometry rather than rebuilding a SwiftUI image hierarchy.
  Screen-frame reports include window movement and are coalesced per view per
  run-loop. Open folder/widget panels receive the current source frame for
  outside-click detection, without publishing additional SwiftUI state.
- Edge summoning uses local/global mouse monitors and click-through panels for
  target geometry and Space membership. No tracking view intercepts input. A
  deliberate outward push arms one reveal delay; clicks, drags, scrolling and
  lateral motion cancel it. A continuous contact is consumed after one reveal.
  Auto-hide retains its separate bounded hide delay. Neither path polls.
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
- Widgets refresh on their own through a single one-shot timer per widget, not
  polling. Calendar wakes at the earliest end of a loaded event or the next
  midnight; Weather wakes when the cached forecast expires. The timer is
  re-armed after each evaluation, after wake, and after day, clock, or time
  zone changes, and is not armed while a widget is disabled or waiting on a
  city or location permission.
- Weather refetches when its request settings (city, current location, unit)
  change, but that refetch waits briefly after the last edit so typing a city
  does not issue a request per keystroke.
- Reduced Motion disables panel frame animation and hover magnification. This is
  both an accessibility requirement and a guard against unnecessary motion work
  on machines where users have opted out of animation.
- The Dock surface uses native SwiftUI Liquid Glass, with a system material
  when Reduce Transparency is enabled.
- Magnification uses a display link while geometry changes and for 100 ms after
  the latest pointer change. The brief input grace period avoids restarting the
  link on every pointer event; unchanged input performs no layout work. The link
  pauses when settled, and the window reserves expansion space so pointer
  movement does not resize its backing surface. Transparent space outside the
  visible Dock passes mouse events through.
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
manual refresh, and once per refresh interval from the widget timer. They should
not repeat every few seconds.

Manual check:

1. Set a manual city in Control Center > Widgets.
2. Open the Weather widget once.
3. Wait at least five minutes without pressing refresh.
4. Use Activity Monitor's Network tab or the unified logs from
   `./script/build_and_run.sh --logs` to confirm there is no tight refresh loop.

The expected behavior is one forecast request when data is missing or stale, then
cached data until the configured refresh interval or a manual refresh.

## Widget Refresh Without Interaction

1. Launch Docking and do not touch it. Calendar and Weather should change from
   Loading to real data without opening a panel or switching apps.
2. In Control Center > Widgets, type a new city. The dock tile should switch to
   the new city shortly after typing stops, and the logs from
   `./script/build_and_run.sh --logs` should show one weather fetch, not one per
   keystroke.
3. Select a single calendar. The dock tile should switch immediately.
4. Create an event that ends a few minutes from now. After it ends, the dock
   tile should move to the next event without any interaction.
5. Repeat the Fast Local Sample with widgets enabled; idle CPU should not change,
   and weather fetches in the logs should be spaced by the refresh interval.

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

1. Enable "Available on every desktop" and "Available over full-screen apps".
   Switch Spaces and enter/exit a full-screen app; confirm no focus stealing.
   Disable these options and confirm edge monitors cannot summon into a Space
   where their target panel is unavailable.
2. In General > Placement display, select Automatic. With separate Spaces and
   two displays, test Auto-hide and Always visible. Crossing displays alone or
   resting at a bottom edge must not move/reveal the Dock. Continue pushing down
   after touching the edge to summon it; repeat all bottom alignments.
3. Select Fixed display and change its target while a reveal is pending. Only
   the selected display may reveal. Disconnect it: fall back to primary, not
   the keyboard-focused screen. Reconnect: Fixed returns; Automatic retains
   its fallback until the next valid summon.
4. Test the effective macOS "Displays have separate Spaces" setting both ways,
   applying any system-required session change. Automatic uses primary only
   when disabled. Fixed remains authoritative.
5. Click and drag bottom-edge controls, scroll there, and slide along the edge
   on noncurrent displays and over Docking's own windows. Input must pass through
   and cancel pending reveals. Test Default, Fast and Instant Edge response.
6. Keep pushing after one reveal, then leave the pointer stationary at the edge
   for 30 seconds. There must be no repeated reveal/layout cycle. Move away and
   repeat the idle CPU/memory sample in both visibility modes after multiple
   display switches and connect/disconnect cycles. Monitors must not accumulate.
7. Repeat icon/widget resizing, app launch/quit, Show Dock and sleep/wake: preserve
   the current eligible display. Compare side edges, stacked displays and
   full-screen second pushes with Apple's Dock before claiming native parity.

Record results in QA.md. Policy tests and a successful build do not prove input
passthrough, physical edge-motion delivery, idle performance or native parity.

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
