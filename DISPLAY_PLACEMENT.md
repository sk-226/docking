# Display placement

## Contract

Placement offers **Automatic** and **Fixed display**. Visibility is a separate choice.

- Automatic starts on the primary display. With `NSScreen.screensHaveSeparateSpaces` enabled, a bottom Dock can be summoned at another display's bottom edge, whether hidden or always visible. Crossing displays with the pointer alone does not move it.
- With separate Spaces disabled, Automatic uses the primary display.
- Fixed display always takes precedence over previous summons, including during Auto-hide. Changes apply immediately without restarting the app.
- Ordinary app/icon updates, resizing and visibility changes keep the current eligible display. Disconnecting it falls back to the primary display (`NSScreen.screens.first`, not the keyboard-focused `NSScreen.main`).
- Fixed mode returns to its requested display on reconnection. Automatic stays on the fallback until another valid summon. A disconnected fixed target remains visible in the picker rather than silently changing the saved preference.
- Pending edge gestures are canceled when placement, trigger topology, visibility or Space-related settings change. The callback also rechecks eligibility before moving the panel.
- Side docks remain on their current eligible display; use Fixed display to place them elsewhere. The physical contact zone and full-screen second-push heuristic are unchanged, but all reveals now require deliberate outward motion. This is not a claim of exact native parity.

There is one pure selection policy, one current display ID, and the existing event-driven edge controller. No cursor polling, private preferences, or parallel legacy placement modes were added. Unknown persisted display choices default only that field to Automatic; other settings are retained.

## Edge gesture and input

Touch the Dock edge, continue moving a little farther toward the outside of the screen, then hold there for the selected Edge response delay. Merely arriving at the edge and waiting does not summon the Dock. Show Dock remains an explicit alternative.

`DockEdgeIntent` ignores the arriving movement and requires 6 points of further outward mouse delta. Partial motion expires after a 0.3-second gap; sideways-dominant or inward movement resets it, as does drifting more than 8 points along the edge. These are initial usability thresholds, not measured Apple Dock constants. They need real mouse and trackpad checks, including slow movement and different display scales.

Clicks, button releases, drags and scrolling cancel pending intent rather than counting as a push. The final delayed callback checks the current pointer, button state, intent and target availability. Each continuous contact is consumed after one reveal. In full-screen-like bottom layouts, the existing second-push gate receives only deliberate pushes, not incidental contact or clicks.

Edge panels are click-through in both Auto-hide and Always visible. They only retain target geometry and Space membership; local/global event monitors observe movement and cancellation events without consuming input. The local monitor returns the original event, and targets outside their active Space are rejected. No tracking-area view or repeating timer is used.

## Automated evidence

On 2026-09-20, all 16 new `DockDisplayPolicyTests` passed under Swift 6.2.1 in an isolated Linux XCTest package. It compiled the actual policy and `Models.swift`; the unused Apple Dock preference importer was stubbed only in that temporary harness. Syntax-only parsing passed for all seven added/edited Swift files. This does not establish AppKit integration or visual correctness.

The review follow-up adds 16 `DockEdgeIntentTests`, passed in Debug and Release on Swift 6.2.1/Linux with the actual intent source and existing second-push gate. It also adds two macOS-only `DockEdgeInputTests` for the click-through panel and monitored event types. These do not prove live input delivery or the physical feel of the gesture.

The existing validation helper defaults its injected separate-Spaces flag to true, modeling independent displays without relying on the test host's setting. Both runtime selection and runtime edge installation explicitly read the live AppKit flag. The pure policy tests cover both flag values.

## Native validation still required

Use the existing Tart VM as documented in DEVELOPMENT.md; do not create or recreate it. Run `./script/tart.sh check`, `./script/tart.sh verify`, and `./script/tart.sh smoke`.

QA.md contains the canonical functional checks; PERFORMANCE.md contains the Spaces/display and idle-performance procedure. Both use Automatic/Fixed and cover Auto-hide and Always visible.

- [ ] Two side-by-side displays: crossing without a summon, deliberate bottom-edge pushes, all bottom alignments, both visibility modes, and separate Spaces enabled/disabled.
- [ ] Fixed target changes during a pending reveal; disconnect/reconnect; primary-display changes; ordinary app updates, sizing, themes and Show Dock preserve the stated selection rules.
- [ ] Underlying bottom controls at 0-1 pt and 4-8 pt remain clickable/draggable. Scrolling, lateral travel, stationary contact and presses during the delay do not summon. Repeat over Docking windows and on other displays.
- [ ] Mouse and trackpad: Default/Fast/Instant response, slow and fast pushes, diagonal approach, different scaling, one reveal per continuous contact and no repeated idle work at the edge.
- [ ] Compare side edges, stacked/partially overlapping displays and full-screen second pushes with Apple's Dock. Repeat with widget/folder panels, restricted Space visibility, sleep/wake and maximum magnification.
