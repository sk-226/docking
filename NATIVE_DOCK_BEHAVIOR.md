# Native Dock behavior checkpoint

The accepted scope (2026-09-22) is basic Dock operations and interaction feel:
launching/switching apps, magnification and pointer tracking, auto-hide, menus,
and reordering apps entirely inside the Dock. Testing must include a crowded
Dock, not just a minimal item list. Complete replication of every Apple Dock
feature and system integration is not the acceptance criterion.

Branch: `feature/native-dock`, base `3800661`. Development uses the existing `docking-dev` Tart VM. The source
snapshot is built at `/private/tmp/docking-native-parity`.

## Crowded Dock changes (2026-09-22)

The fixture started with 32 pinned applications plus running Terminal. The
current review fixture has 33 pinned applications (including Terminal), two
folders and both detailed widgets. The original smaller fixture is backed up
at `/private/tmp/docking-crowded-baseline`; host preferences were not changed.
Actual app bundles are used, rather than mock icons.

- Screen fitting reserves the lens's maximum expansion before choosing the
  resting scale. Previously a full-width dock had zero room left to magnify.
  This is Docking's screen-fit policy, not a claim of recovered Apple fitting.
- SwiftUI resolves the visible list and section boundaries once per Dock body,
  instead of resolving the whole list again for each tile.
- In-Dock reordering updates visible state immediately and writes its final
  order once. Cancel restores the original list without writing intermediate
  permutations. Full window configuration is no longer reapplied at every slot.
- Drag and menu tracking freeze magnification geometry. The dragged tile leaves
  an empty slot while AppKit presents its drag image.
- A mouse-up beyond the five-point threshold completes a Dock-internal reorder
  even when coalesced events arrive after the button is already released. A new
  AppKit dragging session is started only while the left button is still down.
- Dock and edge panels use the SDK's stationary collection behavior, so Show
  Desktop does not hide them. All-Spaces and full-screen options still apply.

A release build moved Calculator and Automator horizontally, Calendar on the
left edge and Calculator on the right edge. Saved order retained all 34 unique
IDs. A 30 second file watch saw one save for the successful drag. More detailed
results and current artifact identity are recorded in the review deliverable.

## Motion follow-up (2026-09-22)

The user's native-vs-Docking smoothness report was treated as a separate issue
from successful operations and low idle CPU.

- A paused display link can deliver a first callback whose target timestamp is
  already in the past. The trace observed targets roughly 135 ms behind the
  callback; using that stale time as the next frame's origin made magnification
  jump to completion. The animation clock now rebases stale targets on callback
  time. The regression test preserves ordinary skipped-frame elapsed time.
- Recent pointer input keeps the display link active for 100 ms; unchanged
  input does not request another layout or prolong that interval. This avoids
  stopping/restarting the link after every steady-state pointer sample while
  still returning to idle after interaction.
- Icon pixels and running indicators now live in retained layers on the existing
  AppKit interaction view. The SwiftUI button still owns the accessible action;
  the same AppKit view reports its screen frame with one deferred notification.
  The separate frame-reporting representable is removed. Launch displacement
  and drag opacity update those layers without rebuilding the image hierarchy.
- Reordering animates surrounding tiles over 270 ms, unless Reduce Motion is on.
  Native `DockBar.moveSpeed` at `0x1002b0e18` returns Float 270; the tile position
  routine at `0x100028008-0x100028048` passes it as duration alongside `mainMillis`.
  Docking uses SwiftUI ease-in-out; exact native interpolation mode for that tile
  property, presentation-frame hit testing, and physical drag parity are not
  claimed from the duration alone.

Temporary instrumentation measured the hosting view's layout work, not GPU
presentation time. In individual crowded entry samples it fell from roughly
5.6 ms to 3.9 ms. A fixed-size SwiftUI image trial did not improve that cost and
was removed. Instrumentation is absent from the review build. Native Dock was
also temporarily populated with the same 33 apps and two folders; the original
VM preferences were restored after comparison. CUA screenshots were roughly
24 Hz and actions can coalesce, so they cannot certify identical continuous
60 Hz physical-pointer motion. This remains a hands-on acceptance check.

## Reference and method

Reference: macOS 26.6.2 (25G83), Dock-2427.6, arm64e. The binary identity and
magnification derivation are in `NATIVE_MAGNIFICATION.md`. Addresses below are
virtual addresses before ASLR. Static inspection recovers instructions and
behavioral formulas, not Apple's original source code. The Swift code is an
independent implementation. No Dock injection, SIP changes or Apple-only
entitlements were used.

The AppKit workspace notification contract was checked in Xcode 26.2's
`NSWorkspace.h`: application notifications carry an `NSRunningApplication`
under `NSWorkspaceApplicationKey`. Public modifier-click behavior is described
in [Apple's Dock guide](https://support.apple.com/ja-jp/guide/mac-help/mh35859/mac).

## Implemented behavior and evidence

| Area | Implementation | Evidence and boundary |
| --- | --- | --- |
| Magnification | Native coordinate warp, direct clamped focus, logarithmic entry/exit duration and cosine interpolation. Pointer is rechecked after geometry changes. | Native instruction references and numeric fixtures. The reviewer's stationary-pointer geometry no longer strands q at 1. Exact native padding, rounding, screen fitting and continuous physical pointer motion are not established. |
| Auto-hide motion | Translates the panel and its hit geometry toward the screen edge. Uses native logarithmic duration and cosine interpolation. New hide-delay default is zero; existing saved delays remain. | Numeric fixtures and all three edge directions are tested. Edge pressure, drag reveal and synchronization of fish/slide timing remain different or unverified. |
| Launch bounce | Reflected parabolic 700 ms cycle, native size-dependent height, completion at the next landing, 120 s timeout. Own launches and workspace will/did-launch notifications feed it. | Native instruction references and numeric tests; process selection tests prevent another instance's tile being used. Complete launch-notification timing, attention requests and hidden-Dock behavior need native comparison. |
| App Exposé | Sends the target PID through `CoreDockSendNotification` after the context menu closes. | In Tart, selecting Show All Windows with keyboard navigation displayed only the inactive System Settings application's windows in native App Exposé. This uses a private ABI, not a promised public API. |
| Input region | The panel uses a WindowServer event region matching visible content, instead of relying only on pointer-driven `ignoresMouseEvents`. | In Tart, a single click from Control Center activated System Settings with magnification off and on; a click through the transparent canvas activated iPhone Mirroring. An integration test applied the private API to an owned panel successfully. |
| Modifier clicks | Command reveals in Finder; Option toggles the active app; Command-Option opens while hiding others. | Dispatch is unit tested. Full live modifier matrix has not been checked. |
| Context menu | AppKit menu in native running-app order: Options, Show All Windows, Hide/Show, Quit. Alternate Option Force Quit item; Finder has no Quit or removal action. Model holds visibility and magnification while tracking. | Native System Settings and Finder menus were inspected in Tart, then the corresponding Docking menus were checked. Keyboard-selected App Exposé worked. Mouse-only menu selection did not invoke App Exposé through CUA; the same automation also failed to select Show View Options in Finder, so physical mouse selection remains unverified. Live Option alternation is unverified because CUA modifier combinations were not forwarded to the guest as expected. |
| Reordering | Native per-axis 5 pt start threshold, AppKit dragging session, screen-coordinate insertion, persistent item order, transient-item pinning, cancel rollback. Finder stays first and applications cannot cross into the file/folder section. | In Tart, Photos moved from the second slot to after Reminders; the saved JSON confirmed the same order. Unit tests cover both ends, vertical coordinates, runtime-field removal and duplicate protection. |
| Drag removal | Native 500 ms grace period and inward boundary; Finder protected. Eligibility is armed only while a mouse button remains pressed. | Boundary tests pass. The CUA outside-drag session required Escape; the item remained and its saved order was restored. A timed release outside the Dock, Escape at all phases and removal feedback still need physical-input testing. |

## Items and section layout

Finder is always present at the first position, including after importing a
native pinned list that does not contain Finder. Its existing stored UUID is
preserved. Application shortcuts precede unpinned running applications; files
and folders come after them. The running and document boundaries both reserve
divider space in layout and magnification. A live native comparison in Tart
showed Terminal and TextEdit between the two dividers, before Downloads.
This does not implement the native recent-app history: currently only running
unpinned apps appear in that middle section.

Local documents can now be added through the picker or an external drop and
imported from native `persistent-others` file tiles. They use their associated
application when clicked. App and folder drops retain their respective kinds.
A document dropped onto an app is opened with that application. In Tart, adding
a temporary text document persisted its `document` kind, clicking it opened the
correct text in TextEdit, and removing its Dock entry left the original file
intact. The temporary Home and document entries were removed after testing.

Finder's menu intentionally says Open: the public launch path opens Finder but
does not create a second window when a Finder window already exists. That
behavior was checked against the guest's Window menu. Native New Finder Window,
New Smart Folder, Find, Go to Folder, Connect to Server and Relaunch still need
their correct action transport. Merely copying those labels would misrepresent
what the implementation actually does.

## Static references

### Auto-hide

- `startAutoHide` at `0x1000a9264` computes visible distance before setting the
  hidden target. `startAutoShow` begins at `0x1000a8f78`.
- Default speed is Float 60, multiplied by `autohide-time-modifier` in
  `0x1002b5868–0x1002b58b0`.
- Duration is `floor(1 + ln(1 + abs(distance)/2)) * 60` milliseconds at modifier 1.
- The property uses interpolation mode 1. Offset at `0x1000e8684` uses
  `(distanceTop + tileSize + distanceBottom + 10) * hideFraction`.
- The VM's native Dock had replacement-mode preferences: delay 1000 and time
  modifier 0. It was briefly shown for comparison and then returned to hidden.
  Those altered preferences are not a native timing baseline. Host preferences
  were not changed.

### Launch bounce

- `handleDockEventAppLaunch` at `0x100107d78`; state initialization at
  `0x100107ebc–0x100107f20` sets a 350 ms half-period and 120000 ms limit.
- Update at `0x10004df10`, normal launch branch `0x10004e0e0–0x10004e130`:
  reflect `(elapsedMilliseconds + 350) mod 700` into `[0,350]`, then evaluate
  `1 - reflected^2 / 350^2`.
- Completion rounds the end to the next 700 ms cycle at `0x10004e068–0x10004e0b0`.
- Height at `0x100028e30` is `6 + 0.2 * (tileHeight - 8)` before the bounce value
  and hide factor. Native 0.2 is Float bit pattern `0x3e4ccccd`.
- The attention-request branch uses a different sequence and is not implemented.

### App Exposé bridge

The loaded HIServices export forwards its second integer argument to Dock's
notification receiver. The receiver for `com.apple.expose.front.awake`
(`0x100098248`, message branch `0x100098314`) passes a nonzero argument to
`_LSASNCreateWithPid` through `0x10011b468`, finds the tile by process serial
number (`0x100034054`), and calls `showForTile:allowSlow:` at `0x100098464`.
The bridge is `(CFString, Int32) -> Int32`; the result is an OSStatus.
The zero argument instead uses the frontmost-app route. Docking does not rely
on a preceding activation request or an arbitrary delay.

The export is resolved dynamically from HIServices. Unavailability and a
nonzero status are logged. Its private ABI may change across OS updates; this
must remain a compatibility risk, not an unconditional claim of native support.

### Input region and drag start

`CGSSetWindowEventShape` is called with connection, window ID and region at
`0x10032ae88`. `CGSNewRegionWithRect` takes a CGRect pointer and a region output
pointer at `0x1000e5464`; `CGSReleaseRegion` releases that region. Docking resolves
these exports from SkyLight and applies them only to its own panel. Content
coordinates are clipped to the canvas and converted to window-local top-left
coordinates. The earlier pointer-driven policy remains if the private interface
is unavailable; that path does not carry the same first-click guarantee.
The API is private and requires compatibility checks on OS updates.

`DockBarMouseEventHandler._handleTileClickEvent:type:` compares each screen
coordinate with its mouse-down coordinate at `0x100112c30–0x100112c60`. A drag
starts only when either absolute difference is greater than 5, not when the
Euclidean distance exceeds 5. Docking now uses that condition so tiny dragged
events cannot turn an ordinary click into a dragging session.

### Drag removal

`DragController.updateRemoveWithEvent:atLocation:` (`0x1000c7580`) requires an
internal drag, an expired grace timer, a removable non-window tile, and a point
outside the menu bar. The 500000000 ns timer is installed at `0x100052c14`.
The inward boundary setup is at `0x10003dde0–0x10003def4`; comparisons are at
`0x1000c770c–0x1000c775c`. In AppKit coordinates Docking uses:

- Bottom: `point.y > frame.maxY + frame.height`.
- Left: `point.x > frame.maxX + frame.width`.
- Right: `point.x < frame.minX - frame.width`.

The coordinate conversion and native integer truncation are not a complete
pixel-equivalence proof. Reordering uses Docking's layout. Native spring loading, animated gap transitions
and every modifier gesture are outside the verified behavior.

## Reviewer's stationary-pointer case

With 16 items, B=36, L=128 and the 1400 by 900 screen fixture, the reported
pointer x=1100.24 was inside the old frame (maxX=1216.290347204904), then outside
the updated frame (maxX=976.995992058974). Replaying the current layout/frame
state code produced `pending-after-geometry=true`, prohibited pausing, and
settled at q=0 without another mouse event. Geometry excluding the pointer is
possible; leaving the display link paused before processing that exit was the
implementation defect. This replay is not a continuous-motion comparison of
both running Docks.

## Outside the basic-interaction scope or not yet verified

- Pixel geometry, native tile inset/baseline, Float/FMA rounding and fitting
  when the Dock cannot fit on the display.
- Auto-hide pressure and delay thresholds, incoming file drags, full-screen
  second-push behavior, display changes and accessibility-setting transitions.
- Native recent-app history and its disabled setting, Trash and volume-eject
  tiles, native Finder menu actions, file aliases/bookmarks and moved-file tracking.
- App-provided Dock menus, badges, progress, dynamic tile content, recent apps
  and Handoff.
- Minimized window thumbnails, minimize/restore effects and native window-list
  actions; Spaces and Mission Control coordination beyond App Exposé.
- Keyboard navigation equivalent to Control-F3; all drag modifiers, spring
  loading, attention bounce, menu anchoring and input timing.
- Current Reduce Motion policy suppresses magnification/bounce and makes
  auto-hide immediate. This policy has not been validated against the reference
  Dock. Static `axReduceMotion` call sites were collected, but that alone does
  not establish the behavior of every animation.

No statement that the entire Dock behaves identically is supported by this
checkpoint. The broader original scope was narrowed to the basic interactions above.

## Current verification (2026-09-22)

The post-review source passes 108 XCTest cases, all 60 validation checks and
debug launch smoke in Tart. Window movement updates icon/widget screen frames;
open folder/widget panels also use the latest source frame for dismissal. The
hidden-list-update reproduction now reports the visible folder frame instead of
the offscreen frame. A live crowded-Dock check confirms folder open/re-click
close with magnification enabled.

Icon layers render at the configured maximum size and display backing scale.
Tests verify Retina dimensions, high-resolution representation selection, and
image reuse while magnifying. These checks do not establish native frame-pacing
parity. The app running in Tart includes these fixes; the preview ZIP below is
the earlier release snapshot. These fixes are included in `feature/native-dock`.

## Pre-review verification (2026-09-22)

The final source passed 105 XCTest cases, all 60 validation checks, the release
package gate and the release launch smoke check in Tart. All 107 build inputs
matched the host worktree by SHA-256. The final release process was PID 13458;
the launch smoke sample reported 0.0% CPU and 133856 KiB RSS. Artifact hashes,
additional idle samples, live checks and remaining limits are in the review
outputs. These samples do not establish a long-duration leak or native frame
pacing guarantee. Changes were uncommitted at that checkpoint.

The new renderer's bottom drag moved Calculator from after Reminders to before
Podcasts, then a right-edge drag moved it between System Settings and TextEdit;
all 35 stored IDs stayed distinct. A left-edge click raised Calculator. Show
Desktop kept the Dock visible. The earlier crowded checkpoint also exercised
left-edge reordering. The review VM is left
at Bottom / Always visible / Instant, magnification on, with the expanded
real-app fixture available for manual review.

Preview ZIP SHA-256:
`3a62f33f6067bf964935e9ca22863eecfe8d920336de73445e870e602387eb48`.
The Git metadata caveat in the historical section also applies to this snapshot.

## Historical verification (2026-09-21)

The 2026-09-21 source snapshot passed all 99 XCTest cases and all 60 framework-free
validation checks in the existing Tart VM. `script/release_check.sh` exited 0:
release build, local signature, source hygiene, production mock boundary,
ZIP/DMG structure and checksums passed. The release launch smoke check also
exited 0; PID 5072 was resident after six seconds at 0.0% CPU and 136000 KB RSS,
with no SwiftUI publish-within-update warning. This is a short launch sample,
not a long-duration performance result.

SHA-256 comparison matched all 108 build-input files (Sources, Tests,
Validation, Resources, script and Package.swift) between the host and guest.
Local preview ZIP SHA-256:
`9850a8487e73555618ff62d195f5a7f22a3c84e7896952423187731d88603bc9`.

The guest source snapshot has no Git metadata. The gate's `Branch: unknown`,
`Commit: unknown` and `Git status: clean worktree` describe that metadata-free
copy; they do not mean the host worktree is clean. The host remains on the
branch and base stated above, with an empty index and uncommitted changes.

The final release build also moved Photos back immediately after Apps in Tart;
the saved item list confirmed the new order, with Finder still first. Temporary
document/Home entries were removed, while the test document itself remained
intact. Native Dock autohide was restored to its pre-comparison value (true).
That checkpoint left Docking at Bottom / Always visible / Instant, with magnification on.
