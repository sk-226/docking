# Display placement

## Contract

Placement offers **Automatic** and **Fixed display**. Visibility is a separate choice.

- Automatic starts on the primary display. With `NSScreen.screensHaveSeparateSpaces` enabled, a bottom Dock can be summoned at another display's bottom edge, whether hidden or always visible. Crossing displays with the pointer alone does not move it.
- With separate Spaces disabled, Automatic uses the primary display.
- Fixed display always takes precedence over previous summons, including during Auto-hide. Changes apply immediately without restarting the app.
- Ordinary app/icon updates, resizing and visibility changes keep the current eligible display. Disconnecting it falls back to the primary display (`NSScreen.screens.first`, not the keyboard-focused `NSScreen.main`).
- Fixed mode returns to its requested display on reconnection. Automatic stays on the fallback until another valid summon. A disconnected fixed target remains visible in the picker rather than silently changing the saved preference.
- Pending edge gestures are canceled when placement, trigger topology, visibility or Space-related settings change. The callback also rechecks eligibility before moving the panel.
- Side docks remain on their current eligible display; use Fixed display to place them elsewhere. The existing edge-contact geometry and full-screen second-push heuristic are unchanged pending comparison with Apple's Dock. This is not a claim of exact native parity.

There is one pure selection policy, one current display ID, and the existing event-driven edge controller. No cursor polling, private preferences, or parallel legacy placement modes were added. Unknown persisted display choices default only that field to Automatic; other settings are retained.

## Automated evidence

On 2026-09-20, all 16 new `DockDisplayPolicyTests` passed under Swift 6.2.1 in an isolated Linux XCTest package. It compiled the actual policy and `Models.swift`; the unused Apple Dock preference importer was stubbed only in that temporary harness. Syntax-only parsing passed for all seven added/edited Swift files. This does not establish AppKit integration or visual correctness.

The existing validation helper defaults its injected separate-Spaces flag to true, modeling independent displays without relying on the test host's setting. Both runtime selection and runtime edge installation explicitly read the live AppKit flag. The new pure tests cover both flag values.

## Native validation still required

Use the existing Tart VM as documented in DEVELOPMENT.md; do not create or recreate it. Run `./script/tart.sh check`, `./script/tart.sh verify`, and `./script/tart.sh smoke`.

- [ ] With two side-by-side displays and separate Spaces enabled: in both visibility modes, cross displays away from the bottom edge (no move), then summon from the other bottom edge (move). Repeat all bottom alignments.
- [ ] Fix display A, try every other screen edge, then change the fixed target to B: only B may reveal the Dock, and a queued A gesture must not move it back.
- [ ] After summoning on B, launch/quit apps, resize icons/widgets, change themes, toggle visibility, and use Show Dock: keep B.
- [ ] Disconnect B, interact with windows on other displays, reconnect B, and change the system primary display. Check the Automatic/Fixed reconnection rules and picker label.
- [ ] Disable separate Spaces and apply the system-required session change. Automatic must remain on primary; explicit Fixed display must remain authoritative.
- [ ] Compare left/right placement, partially overlapping and vertically stacked displays, and full-screen Spaces with Apple's Dock. Record exposed-edge and second-push behavior before changing those heuristics.
- [ ] Repeat with a widget detail panel or folder stack open, with existing Space visibility toggles off, after sleep/wake, and at maximum magnification. Confirm interaction, focus, idle behavior, and launch logs.

The historical multi-display assumptions in QA.md are superseded by the contract above for this change; its broader launch/release gates still apply.
