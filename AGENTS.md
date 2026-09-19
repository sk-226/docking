# Docking agent guidance

## Project

Docking is a native macOS 26 app built with SwiftUI and a small AppKit windowing layer. The package has no external Swift dependencies. Keep SwiftUI as the owner of app state and UI; use AppKit only where macOS windowing, menus, or system integration require it.

Read `DEVELOPMENT.md` for build and signing details. Use `QA.md` for manual behavior checks and `PERFORMANCE.md` for performance-sensitive changes.

## Change policy

- Prefer the smallest coherent change. Do not add compatibility layers, fallback abstractions, or new infrastructure without a concrete need.
- The runtime baseline is macOS 26. Do not add availability branches for older macOS versions.
- Do not duplicate app-bundle, signing, entitlement, or launch logic outside `script/build_and_run.sh`.
- Do not edit `.codex/environments/environment.toml`; it is generated.
- Preserve existing public behavior unless the task explicitly changes it.

## Validation

Use the narrowest relevant check first, then expand only when the change warrants it.

On a host with the Docking Tart VM configured, prefer the VM wrappers so validation runs in a clean macOS 26 + Xcode environment:

```bash
./script/tart.sh check
./script/tart.sh verify
```

For app lifecycle, window, widget, AppKit, or SwiftUI launch changes, also run:

```bash
./script/tart.sh smoke
```

For release or packaging changes, run:

```bash
./script/tart.sh release
```

If Tart is unavailable, use the native equivalents documented in `DEVELOPMENT.md`.

`./script/tart.sh setup` downloads and creates a VM. Agents must not create, delete, or replace Tart VMs unless the user explicitly asks for that operation. If the VM has not been bootstrapped, report that `./script/tart.sh setup` is required instead of silently downloading an image.

Do not claim visual correctness from headless checks. UI changes still need the applicable manual checks from `QA.md`.