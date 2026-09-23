# Native magnification model

The magnification curve and entry/exit timing come from a static analysis of
the Apple Dock in the existing Tart VM on 2026-09-21. This is an independent
Swift implementation of the recovered arithmetic, not recovered Apple source.

## Reference binary

- macOS 26.6.2, build 25G83; Dock-2427.6.
- `/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock`, arm64e slice.
- Universal binary SHA-256:
  `10d4bacc207d9dd51ff6940f7a18cf151a6196d29d27cb6b8482600bff6b4952`.
- Addresses below are image virtual addresses before ASLR.
- `nm`, `otool -ov` and `llvm-objdump --macho --arch=arm64e -d` exposed the
  instruction stream. Objective-C relative method lists and selector stubs
  connected it to `DockBar` methods.

## Recovered arithmetic

Let B be `tileSize`, L be `largeSize`, c be `fishCenter`, and q be the current
`fish` animation value. With magnification enabled and L > B:

```text
R = 3 B
A = ((L - B) / 2) / sin(pi B / (4 R)) * q
d = x - c

F(x) = x - A                      if d <= -R
       x + A sin(pi d / (2 R))     if -R < d < R
       x + A                      if d >= R
```

The parameter setup is at `0x100028690–0x1000287c8`; the first coordinate
transformation is at `0x1000288c0–0x10002893c`. Both ends of the base-width
interval are transformed, and `0x100028ab4` takes their difference.
`DockBar.fSize` at `0x1002b0e3c` returns 3.

The source constant is float bit pattern `0x40490fdb`, also stored promoted to
double at `0x10036f218`. It is not Swift's `Float.pi` constant. Docking preserves
this value, but computes geometry in Double; the native mix of float/double
rounding and fused operations is not reproduced bit for bit.

`startFishing` (`0x1000a8e00`) targets q = 1; `stopFishing` (`0x1000a8f3c`)
targets q = 0. The non-dragging branch at `0x1000a8e98–0x1000a8ed0` uses:

```text
durationMilliseconds = floor(1 + 42 ln(1 + remainingSizeDifference / 2))
remainingSizeDifference = (L - B) abs(targetQ - currentQ)
```

`DockBar.fishSpeed` at `0x1002b0e30` returns 42. The fish property is initialized
in mode 1 at `0x1002b5904–0x1002b5914`; the getter and initialization both refer
to the field offset at `0x100485308`. The update routine at
`0x10008d2e4–0x10008d38c` transforms normalized elapsed time u with
`(1 - cos(pi u)) / 2`, then interpolates from the saved starting value to the
target. The target is assigned exactly on completion.

## Docking integration

- The same coordinate transform expands icon widths and the gaps between
  icons. Expanding widths alone would make the total length oscillate during
  a sweep. With a complete interior lens, growth is constant at
  `(L - B) / sin(pi / 12)`.
- `iconLeadingInsets` gives SwiftUI the extra gap before each icon. The
  running-app divider keeps its own thickness; any extra expansion across its
  gap is placed before the following icon. Widgets and the add button retain
  their original sizes.
- `fishCenter` follows the pointer coordinate directly, clamped to the resting
  bar bounds. The previous inverse-coordinate solver and end fade were removed.
  The native clamp is at `0x10002854c–0x100028690`. Bar placement precedes the
  transform (`0x1000280d4–0x1000284cc`); Docking derives its origin from the first
  transformed interval instead of recentering the expanded width.
- The existing screen-room constraint scales the expansion amplitude if the
  Dock cannot fit, and constrains the panel's origin shift. A fixed panel canvas
  now reserves the maximum expansion of the recovered curve, including small
  item counts and the gaps between them.
- Entry and exit animate q with the recovered timing. Moving between icons
  does not restart entry. Exit retains the latest valid focus while q returns
  to zero. Pointer residency is checked again after applying each frame, before
  pausing the display link. A newly queued exit therefore cannot be stranded.
- Residency uses `max(restThickness, B + edgeInset + currentFish) + 10`, rather
  than the tallest sampled icon. Native `inBarRect` starts at `0x1000293a8`;
  it also expands the two long-axis edges by `distanceSides` and rounds to the
  nearest pixel. Docking retains its own padding and screen-room constraint.
- Reduce Motion still disables magnification; changes of settings, item count
  or display reset the animation. The compact surface frame remains anchored
  to its screen edge, preserving the previous short-axis jitter correction.

Screen fitting, divider handling, widgets, accessibility policy and the drag
layout remain Docking policies. Native tile inset, precise Float/FMA rounding,
external-fish-tile focus and the dragging `moveSpeed` branch are not reproduced.
The additional Dock work and remaining full-scope differences are tracked in
`NATIVE_DOCK_BEHAVIOR.md`. This is not complete system-Dock equivalence.

## Validation

Reference fixtures include 36 -> 128 point magnification. The recovered
interior expansion is 355.46069440980796 points; widths at center distances
0, 36, 72 and 108 are 128, 115.67433647792706, 81.99999767821596 and
42.056013048760974 points. A 64 point size difference takes 147 ms; a 92 point
difference takes 162 ms.

Tests cover these fixtures, gap accounting, constant interior length,
pointer targeting and monotonicity, all placements and screen constraints,
entry/exit reversal, repeated input, skipped frames, 60/120/240 Hz equivalence,
exact idle settlement, disabled magnification and unchanged surface thickness.
Runtime evidence for the review build is recorded in `MAGNIFICATION_HANDOFF.md`.
