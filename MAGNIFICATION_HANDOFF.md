# Dock appearance and magnification checkpoint

Status: implementation checkpoint, not a claim of Apple Dock motion parity.
The next pass should finish motion behavior before treating the UI as complete.

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
- Size and origin now interpolate together. Previously the latest pointer
  position recomputed the origin from partially animated icon sizes, causing
  large sideways jumps on fast movement and reversal.
- A fixed NSPanel canvas holds the moving content. Pointer residency and detail
  panel anchors use the visible content frame, not the reserved canvas.
- CADisplayLink replaces a 60 Hz Timer. Its requested frame range follows the
  display; default adaptive cadence dropped toward 30 Hz in the VM. Elapsed time
  uses the monotonic clock because the first resumed target timestamps were
  irregular in this environment. The link pauses after settling.

Relevant files: `DockLayout.swift`, `DockView.swift`, and
`Windowing/DockPanelController.swift` under `Sources/DockingCore`.

## Remaining motion issue

`DockLayout.metrics` still computes `originShift` using a piecewise fraction of
each icon's growth. Even with a constant total width, that target moves sideways
as the pointer crosses a single icon. Interpolating the entire geometry removes
the large transient jump but does not remove this smaller periodic target motion.

A direct calculation with 16 icons, base size 36, magnification size 128, and the
pointer moving from interior icon center 6 to center 7 gives:

| Fraction between centers | Total growth | Origin shift |
| --- | --- | --- |
| 0 | 184 | 92.000 |
| 0.25 | 184 | 97.425 |
| 0.375 | 184 | 97.952 |
| 0.5 | 184 | 92.000 |
| 0.625 | 184 | 86.048 |
| 0.75 | 184 | 86.575 |
| 1 | 184 | 92.000 |

This is a remaining mathematical discrepancy, not evidence that the current
checkpoint matches the native clip. Compare a stable centered origin and a
continuous inverse mapping between screen coordinates and resting icon
coordinates. Preserve targeting near the two ends and screen-edge clamping;
blindly centering the growth can move the peak away from the pointer there.

The current regression test covers rapid transitions between icon centers,
reversal, 60/120 Hz timing, exit, and the fixed canvas on every edge. Extend it
with sub-icon sweeps when deciding the correct mapping.

## Validation evidence

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
- No final end-to-end comparison of the corrected motion against the native
  recording has passed. Multi-display, full-screen, and accessibility changes
  need the applicable QA checks.

## Tart source transfer

The VM already exists; do not recreate it. The shared folder showed stale file
contents during in-place host edits in this session. An exact tar snapshot sent
through `tart exec -i` avoided that issue. Use a guest-local source directory and
scratch directory for a trustworthy build:

```bash
COPYFILE_DISABLE=1 tar --no-xattrs -cf - Package.swift Sources Validation script Resources |
  tart exec -i docking-dev /bin/zsh -lc \
  'mkdir -p /private/tmp/docking-ui-work && tar -xf - -C /private/tmp/docking-ui-work'

tart exec docking-dev /bin/zsh -lc \
  'cd /private/tmp/docking-ui-work && swift run --scratch-path /private/tmp/docking-ui-build DockingValidation'

tart exec docking-dev /bin/zsh -lc \
  'cd /private/tmp/docking-ui-work && SWIFTPM_SCRATCH_PATH=/private/tmp/docking-ui-build ./script/launch_smoke_check.sh'
```

These temporary directories can disappear after a VM restart. The host checkout
is authoritative. Do not infer that the source mount is fresh merely because
it is present. The existing unrelated untracked plan documents are not part of
this checkpoint.
