# Dock appearance and magnification checkpoint

Status: the magnification coordinate transform and entry/exit animation now
use arithmetic recovered from the Apple Dock in Tart. Implementation details,
binary provenance, reference values and limits are in `NATIVE_MAGNIFICATION.md`.
Full behavioral parity with Apple Dock remains unverified.

## Basic Dock interaction checkpoint (2026-09-22)

The accepted scope is basic Dock operations and interaction feel, including
in-Dock reordering and behavior with many items. It does not require replicating
every Apple Dock integration. `NATIVE_DOCK_BEHAVIOR.md` records implementation,
native evidence, current Tart observations and remaining verification limits.

Review branch: `feature/native-dock`, based on `3800661`.
Tart builds an exact source snapshot at `/private/tmp/docking-native-parity`.
The current crowded fixture has 33 pinned applications,
two folders and both detailed widgets. It exposed missing magnification when
screen-fitting, repeated saves during reordering, Show Desktop hiding the dock,
and lost quick drags. Those paths are now addressed. Bottom, left and right
reordering were exercised with the real apps and persisted order was checked.

The smoothness follow-up adds retained icon layers, coalesced frame reporting,
a short display-link input grace period, a stale-target clock correction, and
270 ms reorder transitions. The final candidate passed 105 XCTest cases and
60 validation checks. Temporary layout measurements improved from roughly
5.6 ms to 3.9 ms in individual entry samples; this is not proof of identical
native frame pacing. The native comparison and its limits are recorded in
`NATIVE_DOCK_BEHAVIOR.md`.

The later review fixes refresh click geometry when the Dock window moves and
when an open panel's source icon moves. Icon pixels now cover the configured
maximum magnification and display backing scale while retaining the image across
animation frames. The current source passed 108 XCTest cases, 60 validation
checks and debug launch smoke in Tart, plus a live folder open/re-click close
check. The earlier release ZIP has not been refreshed for these fixes.

## Historical native arithmetic review build (2026-09-21)

The following 73-test checkpoint predates the broader changes above. Its
pointer-inverse statement and verification results describe that earlier
snapshot, not the current implementation.

Branch: `feature/native-dock`, based on `3800661`.

The coordinate warp expands both icon widths and their intervening gaps.
Entry/exit animates one magnification value with the native logarithmic duration
and cosine easing; cursor movement does not restart that animation. The
deterministic pointer inverse, screen constraints, widgets and compact surface
anchor remain Docking policies. The native dragging timing branch is not
implemented.

In the existing `docking-dev` VM, macOS 26.6.2, Xcode 26.2 / Swift 6.2.3:

- All 73 XCTest cases and all 60 `DockingValidation` checks passed.
- The normal app built, launched and passed `script/launch_smoke_check.sh`.
- `script/release_check.sh` passed, including the release build, local signature,
  source hygiene, production mock boundary, zip/DMG contents and checksums.
  The guest source snapshot has no Git metadata; branch and base commit above
  describe the host worktree, whose changes remain uncommitted for review.
- Live checks covered bottom, left and right placement. Magnified icons were
  visible beyond the compact glass; clicking that outer part of System Settings
  opened the application in all three placements.
- The review session returned to bottom placement. Test/build source was
  transferred as a tar snapshot to `/private/tmp/docking-native-magnification`;
  the normal application is its `dist/Docking.app`.

The previous motion-replay cadence and zero short-axis range measurements below
belong to earlier builds. They were not remeasured for this curve. Automated
tests cover geometry, timing and settlement; static UI checks do not establish
frame pacing or full native motion parity. Physical auto-hide gestures,
multi-display/full-screen behavior and accessibility preference changes were
not manually retested.

## Earlier checkpoints

The remaining evidence describes the earlier custom curve and its fixes.
Its radius, expansion figures and whole-layout interpolation are superseded by
the native arithmetic section above; retain it as regression history.

## Short-axis jitter correction (2026-09-20)

PR #20 (`42c07c8`) still allowed the SwiftUI content frame to change thickness
on every magnification update. Its screen-edge offset used the unrounded
expanded thickness, while SwiftUI aligned the content on its pixel grid.
A deterministic horizontal sweep in the existing Tart VM exposed a 0.49924 pt
vertical range in an icon outside the magnification lens. Its horizontal
position was constant, and the NSPanel frame did not change.

The fix lays out the foreground in the compact surface frame and anchors that
frame to the same screen edge. Enlarged icons overflow inward; expanded panel
geometry still controls pointer residency and click-through behavior.
The magnification curve, timing, and Liquid Glass foreground treatment are
unchanged.

Using direct SwiftUI image-frame measurements, the same 12-icon sweep at
36 -> 79 pt produced a 0 pt vertical range after the fix. At 27 -> 60 pt,
the fixed-axis range was also 0 pt in bottom, left, and right placement.
AppKit frame reports alone rounded away this residual motion, so they are not
sufficient evidence for this regression. Temporary replay and measurement
code were confined to the test copy, not the production source.

After removing instrumentation, Show Docking displayed the normal build in
Tart. Moving onto Calendar enlarged it, and clicking its portion above the
glass activated Calendar. The clean PR #20 plus fix passed all 64 XCTest cases,
DockingValidation, and the launch smoke check without a publish-within-update
warning. Physical edge summoning and the broader Auto-hide matrix were not
retested. This isolates one source of jitter; it does not establish Apple Dock
motion parity or eliminate every possible rendering hitch.

## Intended behavior

Make Docking feel as close as possible to Apple's Dock. Keep original app icons,
compact glass, a small add button, and widgets that do not force excess Dock
height. Dock size, widget size, and magnification are adjustable. Development
and app launches belong in Tart.

The original conversation contains two reference clips: the 13.08.13 recording
shows the desired native behavior, and the 13.09.13 recording shows the previous
jerky implementation. The recordings are not included in this repository.

## Implemented

- Original icon rendering, compact indicators and add button, a native glass
  surface, compact widgets, size sliders, and Apple Dock size import.
- Magnification enlarges adjacent icons with a cosine profile and allocates real
  space between them. Widgets keep their resting size.
- Size and origin interpolate together. The latest pointer does not recompute
  the origin from partially animated icon sizes.
- A fixed NSPanel canvas holds the moving content. Pointer residency and detail
  panel anchors use the visible content frame, not the reserved canvas.
- CADisplayLink follows the display cadence and pauses after settling. The
  existing elapsed-time interpolation and accessibility behavior are preserved.
- The target origin now centers total growth, constrained by the available room
  on each side. Pointer movement inside an interior icon no longer translates
  the whole Dock periodically.
- Pointer coordinates are mapped back to resting coordinates through enlarged
  icon centers. The mapping includes screen clamping before choosing the
  magnification peak, including top-to-bottom order on vertical docks.

Relevant files: `DockLayout.swift`, `DockView.swift`, and
`Windowing/DockPanelController.swift` under `Sources/DockingCore`.
Regression tests: `Tests/DockingCoreTests/DockMagnificationTests.swift`.

## Target-coordinate correction

The previous `DockLayout.metrics` computed `originShift` from piecewise fractions
of individual icons' growth. Its total width could remain constant while its
origin oscillated as the pointer crossed one icon.

For 16 icons, base size 36, magnification size 128, and a pointer moving from
interior icon center 6 to center 7:

| Fraction between centers | Total growth | Previous origin shift | Corrected origin shift |
| --- | --- | --- | --- |
| 0 | 184 | 92.000 | 92.000 |
| 0.25 | 184 | 97.425 | 92.000 |
| 0.375 | 184 | 97.952 | 92.000 |
| 0.5 | 184 | 92.000 | 92.000 |
| 0.625 | 184 | 86.048 | 92.000 |
| 0.75 | 184 | 86.575 | 92.000 |
| 1 | 184 | 92.000 | 92.000 |

Simply centering growth is insufficient at the ends or against a screen edge.
The corrected model solves for the resting focus whose position between enlarged
icon centers matches the pointer. It uses a bounded bisection against target
geometry, not a feedback loop through the current animation state.

The inverse uses center-to-center interpolation, not the previous piecewise
within-icon fractions: those fractions can produce a non-monotone mapping at
large magnification. Beyond the first/last center, continuous extensions retain
the two-pitch cosine falloff in pointer coordinates, rather than pinning the end
icon while the pointer crosses padding or widgets. That end behavior still needs
comparison with the native reference; it is not an extracted Apple algorithm.

`DockMagnificationBounds` carries unscaled leading/trailing screen room into the
solver. For vertical docks, leading means above the first icon. Total growth is
also capped by that room, so the final window clamp does not move the target away
from the pointer. No Apple Dock preferences, VM configuration, rendering cadence,
widget sizing, or animation time constants are changed by this correction.

## Initial isolated validation

On 2026-09-19, Swift 6.2.1 on Linux, in an isolated harness:

- All 10 XCTest cases passed in both Debug and Release configurations.
- The harness compiled the actual `DockLayout.swift` and the pure geometry enums
  extracted unchanged from `DockPanelController.swift`. A minimal settings
  fixture supplied the layout properties from `Models.swift`; it did not replace
  the magnification implementation with a separate model.
- Coverage includes sub-icon sweeps/reversal, center-target accuracy at both
  ends and dividers, monotonicity across supported icon sizes and constrained
  growth, inverse round trips, continuous end falloff, translated screen bounds,
  true bottom-left/right alignment, all Dock edges, 0/1/16/70 icons, fixed-canvas
  containment, 60/120/240 Hz elapsed-time equivalence, and exact exit settlement.
- Disabled magnification, non-finite pointer input, no expansion room, and
  unchanged glass/widget thickness are also covered.
- The edited AppKit controller passed a Swift syntax-only parse. Its framework
  integration was not typechecked or launched on macOS in this environment.

These initial checks covered geometry only. Subsequent macOS validation is
recorded below. Both `script/tart.sh check` and `script/tart.sh validate` now run
`DockingValidation` and the XCTest suite. `script/release_check.sh` runs both
suites as part of the GitHub Actions release-candidate workflow.

## Native validation of the coordinate mapping

On 2026-09-19, in the existing `docking-dev` VM, macOS 26.6.2, Swift 6.2.3:

- All 10 XCTest cases and all 60 `DockingValidation` checks passed.
- After adding XCTest to the standard gates, `script/tart.sh check` and
  `script/tart.sh release` both passed, including zip/DMG checksum verification.
- The app bundle built and verified, and the launch smoke check passed.
- A temporary deterministic replay exercised sub-icon movement, reversal,
  traversal, the ends, the widget side, and exit. The interior target origin
  stayed at 92 pt, and the NSPanel frame had exactly one value throughout.
- During continuous animation, 590 display intervals had a median of 16.67 ms,
  95th percentile of 17.88 ms, and maximum of 18.06 ms. Longer wall-clock gaps
  occurred while the display link was paused outside the magnification area.
- Actual SwiftUI frame reports were collected; all 12 icons returned to their
  36 pt resting size after exit. A settled idle sample showed 0.0% CPU.
- Live UI checks covered bottom, left, and right placement with 128 pt maximum
  magnification. Clicking an enlarged System Settings icon activated that app.
- The replay and instrumentation existed only in the guest. They were removed,
  source hashes were checked, and a normal app bundle was built and verified.

These checks establish the coordinate correction and the measured VM cadence.
They do not establish motion parity with the Apple Dock reference recording.

## Previous checkpoint evidence (before this correction)

On 2026-09-19, in the existing `docking-dev` VM, macOS 26.6.2:

- The 60-check validation executable and launch smoke check passed.
- A temporary deterministic pointer replay traversed the icons back and forth
  for 10 seconds and then exited. Actual SwiftUI frame reports were collected.
- After requesting the display cadence, 619 animation callbacks covered 10.30
  seconds including settling: median interval 16.69 ms, 95th percentile 17.57 ms,
  maximum 17.81 ms. The NSPanel frame had exactly one value throughout the run.
- Every icon returned to its resting size after exit.
- The replay and instrumentation existed only in the guest and were removed
  before the final normal build. They are not production features.
- Static UI checks covered the three Dock edges, sliders, widget open/close,
  and the add picker. Those checks do not establish continuous native parity.

The Appearance and magnification entry in `QA.md` separates these earlier UI
checks from validation of the current coordinate mapping.

## Remaining native comparison

Compare the 13.08.13 native reference with Docking at the same icon size, maximum
magnification, item order, screen scale, and pointer path. Include slow sub-icon movement,
fast traversal/reversal, both ends, dividers, widgets, diagonal entry/exit,
bottom/left/right placement, and screen-edge clamping. Check click targeting,
auto-hide residency, and idle settling as well as appearance.

No final end-to-end comparison against the native recording has passed for this
correction. Multi-display, full-screen, and accessibility changes still need the
applicable `QA.md` checks. Do not label this change "identical to Apple Dock"
until that comparison is recorded.

## Tart source transfer

The VM already exists; do not recreate it. The shared folder showed stale file
contents during in-place host edits in the earlier session. An exact tar snapshot
sent through `tart exec -i` avoided that issue. Use a guest-local source directory
and scratch directory for a trustworthy build. Include `Tests` now that the
package declares a test target:

```bash
COPYFILE_DISABLE=1 tar --no-xattrs -cf - Package.swift Sources Validation Tests script Resources |
  tart exec -i docking-dev /bin/zsh -lc \
  'mkdir -p /private/tmp/docking-ui-work && tar -xf - -C /private/tmp/docking-ui-work'

tart exec docking-dev /bin/zsh -lc \
  'cd /private/tmp/docking-ui-work && swift test --scratch-path /private/tmp/docking-ui-build --filter DockMagnificationTests'

tart exec docking-dev /bin/zsh -lc \
  'cd /private/tmp/docking-ui-work && swift run --scratch-path /private/tmp/docking-ui-build DockingValidation'

tart exec docking-dev /bin/zsh -lc \
  'cd /private/tmp/docking-ui-work && SWIFTPM_SCRATCH_PATH=/private/tmp/docking-ui-build ./script/launch_smoke_check.sh'
```

These temporary directories can disappear after a VM restart. The host checkout
is authoritative. Do not infer that the source mount is fresh merely because
it is present. The existing unrelated untracked plan documents are not part of
this checkpoint.
