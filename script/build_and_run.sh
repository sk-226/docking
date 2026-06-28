#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Docking"
BUNDLE_ID="com.sugu.docking"
APP_VERSION="0.0.0"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SWIFTPM_SCRATCH_PATH="${SWIFTPM_SCRATCH_PATH:-/private/tmp/docking-app-swiftpm-run}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

# The run script is the path users hit most often from Codex and Finder. Keeping
# its SwiftPM build database in /private/tmp avoids coupling launch reliability
# to a possibly stale project-local .build directory, while still producing the
# same executable from the current source tree. The directory name is deliberately
# lowercase even though the product is Docking: APFS is often case-insensitive,
# and Swift/Clang module caches can collide when two scratch paths differ only
# by case. We do not delete this scratch path on every run because incremental
# builds matter for an app that will be launched repeatedly during UI tuning.
swift build --product "$APP_NAME" --scratch-path "$SWIFTPM_SCRATCH_PATH"
BUILD_BINARY="$(swift build --scratch-path "$SWIFTPM_SCRATCH_PATH" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSCalendarsUsageDescription</key>
  <string>Docking shows your upcoming events in the calendar widget.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Docking needs full calendar access to read upcoming events for the calendar widget.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Docking can use your location for the weather widget when you enable current-location weather.</string>
  <key>NSLocationUsageDescription</key>
  <string>Docking can use your location for the weather widget when you enable current-location weather.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
