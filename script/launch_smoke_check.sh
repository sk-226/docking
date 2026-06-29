#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Docking"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

section() {
  printf '\n==> %s\n' "$1"
}

section "Build and launch"
"$ROOT_DIR/script/build_and_run.sh" --verify

section "Resident process"
# `build_and_run.sh --verify` proves the app exists one second after launch.
# This smoke check waits a little longer because Docking is a resident utility:
# release readiness requires it to survive the first SwiftUI/AppKit layout pass,
# weather/location initialization, and menu-bar setup rather than merely flash
# into existence long enough for LaunchServices to report a process.
sleep 5
pid="$(/usr/bin/pgrep -x "$APP_NAME" | /usr/bin/head -n 1 || true)"
if [[ -z "$pid" ]]; then
  printf 'Launch smoke check failed: %s is not running after the settle window.\n' "$APP_NAME" >&2
  exit 1
fi

/bin/ps -o pid,%cpu,rss,etime,command -p "$pid"

section "SwiftUI runtime warnings"
# The local release gate intentionally does not launch the app, because package
# inspection should not mutate permissions, windows, or user defaults. This
# separate smoke script owns launch-only checks, including the warning that
# previously blanked the Control Center during the first scene update.
if /usr/bin/log show --style compact --last 30s \
  --predicate "process == \"$APP_NAME\" AND eventMessage CONTAINS \"Publishing changes from within view updates\"" |
  /usr/bin/grep -q "Publishing changes from within view updates"; then
  printf 'Launch smoke check failed: SwiftUI publish-within-update warning was logged.\n' >&2
  exit 1
fi

printf 'Launch smoke check passed for %s (pid %s).\n' "$APP_NAME" "$pid"
