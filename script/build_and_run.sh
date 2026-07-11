#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Docking"
BUNDLE_ID="app.docking.docking"
APP_VERSION="0.0.4"
MIN_SYSTEM_VERSION="26.0"
CONFIGURATION="${CONFIGURATION:-debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
PACKAGE_ZIP="$DIST_DIR/$APP_NAME-$APP_VERSION-macos26.zip"
RESOURCES_DIR="$ROOT_DIR/Resources"
APP_ICON_RESOURCE="$RESOURCES_DIR/DockingAppIcon.icns"
MENU_BAR_ICON_RESOURCE="$RESOURCES_DIR/DockingMenuBarTemplate.png"
WEATHERKIT_ENTITLEMENTS_PLIST="$RESOURCES_DIR/DockingWeatherKit.entitlements"

case "$CONFIGURATION" in
  debug)
    DEFAULT_SCRATCH_PATH="/private/tmp/docking-app-swiftpm-run"
    ;;
  release)
    DEFAULT_SCRATCH_PATH="/private/tmp/docking-app-swiftpm-release-run"
    ;;
  *)
    echo "CONFIGURATION must be debug or release, got: $CONFIGURATION" >&2
    exit 2
    ;;
esac

SWIFTPM_SCRATCH_PATH="${SWIFTPM_SCRATCH_PATH:-$DEFAULT_SCRATCH_PATH}"
SWIFTPM_CONFIGURATION_ARGS=(-c "$CONFIGURATION")

detect_code_sign_identity() {
  if [[ -n "${DOCKING_CODE_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$DOCKING_CODE_SIGN_IDENTITY"
    return
  fi

  # macOS privacy permissions are tied to code identity. Leaving the staged app
  # as a bare SwiftPM executable makes the embedded adhoc identifier look like
  # `Docking-<hash>`, so Calendar and Location can be prompted again after a
  # rebuild. Prefer a real local Apple Development identity when one exists; it
  # gives TCC a stable requirement while keeping the script usable on machines
  # that only have adhoc signing available.
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null |
    /usr/bin/sed -n 's/.*"\(Apple Development:.*\)"/\1/p' |
    /usr/bin/head -n 1 || true
}

profile_supports_weatherkit() {
  local profile_path="$1"
  local decoded_profile
  local app_identifier
  local has_weatherkit

  decoded_profile="$(mktemp "${TMPDIR:-/tmp}/docking-weatherkit-profile.XXXXXX.plist")"
  if ! /usr/bin/security cms -D -i "$profile_path" -o "$decoded_profile" >/dev/null 2>&1; then
    rm -f "$decoded_profile"
    return 1
  fi

  app_identifier="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$decoded_profile" 2>/dev/null || true)"
  has_weatherkit="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.weatherkit' "$decoded_profile" 2>/dev/null || true)"
  rm -f "$decoded_profile"

  [[ "$app_identifier" == *".$BUNDLE_ID" && "$has_weatherkit" == "true" ]]
}

detect_weatherkit_profile() {
  local profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
  local profile_path

  if [[ -n "${DOCKING_WEATHERKIT_PROFILE:-}" ]]; then
    printf '%s\n' "$DOCKING_WEATHERKIT_PROFILE"
    return
  fi

  [[ -d "$profiles_dir" ]] || return 0

  # WeatherKit is a restricted entitlement, not a normal framework capability.
  # Codesign can attach the key from a local plist, but macOS will refuse to
  # launch the app unless an Apple-issued provisioning profile proves that this
  # Team/App ID is allowed to use it. That means other people who clone Docking
  # and build it locally will also get Open-Meteo unless they provision their
  # own bundle ID, or unless they run a distribution build signed by someone who
  # has enabled WeatherKit for this app. Auto-detecting a matching local profile
  # keeps ordinary pre-release development builds launchable while letting a properly
  # provisioned machine use WeatherKit without a second signing script.
  while IFS= read -r profile_path; do
    if profile_supports_weatherkit "$profile_path"; then
      printf '%s\n' "$profile_path"
      return
    fi
  done < <(/usr/bin/find "$profiles_dir" \( -name '*.provisionprofile' -o -name '*.mobileprovision' \) -print 2>/dev/null)
  return 0
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

# The run script is the path users hit most often from Codex and Finder. Keeping
# its SwiftPM build database in /private/tmp avoids coupling launch reliability
# to a possibly stale project-local .build directory, while still producing the
# same executable from the current source tree. The directory name is deliberately
# lowercase even though the product is Docking: APFS is often case-insensitive,
# and Swift/Clang module caches can collide when two scratch paths differ only
# by case. We do not delete this scratch path on every run because incremental
# builds matter for an app that will be launched repeatedly during UI tuning.
#
# Release packaging intentionally reuses this staging path instead of maintaining
# a second app-bundle builder. The trade-off is that this script has a small
# configuration switch, but the important bundle metadata, permission strings,
# signing identity, and LaunchServices behavior stay in exactly one place.
swift build "${SWIFTPM_CONFIGURATION_ARGS[@]}" --product "$APP_NAME" --scratch-path "$SWIFTPM_SCRATCH_PATH"
BUILD_BINARY="$(swift build "${SWIFTPM_CONFIGURATION_ARGS[@]}" --scratch-path "$SWIFTPM_SCRATCH_PATH" --show-bin-path)/$APP_NAME"

if [[ ! -s "$APP_ICON_RESOURCE" || ! -s "$MENU_BAR_ICON_RESOURCE" ]]; then
  echo "Missing Docking icon resources. Run ./script/render_icons.swift before building the app bundle." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$APP_ICON_RESOURCE" "$APP_RESOURCES/DockingAppIcon.icns"
cp "$MENU_BAR_ICON_RESOURCE" "$APP_RESOURCES/DockingMenuBarTemplate.png"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>DockingAppIcon</string>
  <key>CFBundleIconName</key>
  <string>DockingAppIcon</string>
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
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Docking can use your location for the weather widget when you enable current-location weather.</string>
  <key>NSLocationUsageDescription</key>
  <string>Docking can use your location for the weather widget when you enable current-location weather.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

CODE_SIGN_IDENTITY="$(detect_code_sign_identity)"
if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  CODE_SIGN_IDENTITY="-"
fi
WEATHERKIT_PROFILE="$(detect_weatherkit_profile)"

# Sign the completed bundle, not only the executable. The Info.plist must be
# sealed into the signature so LaunchServices, TCC, and Activity Monitor all see
# one stable app identity during repeated debug launches. The identifier is
# deliberately product-scoped rather than user-scoped because it can show up in
# screenshots, logs, and eventual GitHub-visible artifacts.
#
# WeatherKit is included only when the matching provisioning profile is present.
# A local entitlement plist alone is actively harmful here: WeatherKit is a
# restricted entitlement, so macOS rejects the launch with "No matching profile
# found" before Docking can even fall back to Open-Meteo. We deliberately do not
# make every local user solve Apple's paid provisioning flow just to see weather;
# Open-Meteo remains the honest default for unprovisioned builds, and WeatherKit
# becomes active only when the signature can prove this bundle is allowed to use
# Apple's service.
CODE_SIGN_ARGS=(--force --sign "$CODE_SIGN_IDENTITY" --timestamp=none)
if [[ -n "$WEATHERKIT_PROFILE" ]]; then
  if [[ ! -s "$WEATHERKIT_PROFILE" ]]; then
    echo "WeatherKit provisioning profile does not exist: $WEATHERKIT_PROFILE" >&2
    exit 1
  fi
  if [[ ! -s "$WEATHERKIT_ENTITLEMENTS_PLIST" ]]; then
    echo "Missing Docking WeatherKit entitlements file: $WEATHERKIT_ENTITLEMENTS_PLIST" >&2
    exit 1
  fi
  if ! profile_supports_weatherkit "$WEATHERKIT_PROFILE"; then
    echo "Provisioning profile does not grant WeatherKit for $BUNDLE_ID: $WEATHERKIT_PROFILE" >&2
    exit 1
  fi

  cp "$WEATHERKIT_PROFILE" "$APP_CONTENTS/embedded.provisionprofile"
  CODE_SIGN_ARGS+=(--entitlements "$WEATHERKIT_ENTITLEMENTS_PLIST")
else
  echo "WeatherKit entitlement not attached: no matching provisioning profile found for $BUNDLE_ID; Weather will fall back to Open-Meteo." >&2
fi
/usr/bin/codesign "${CODE_SIGN_ARGS[@]}" "$APP_BUNDLE"

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
  --package|package)
    # Package mode deliberately stops after bundle staging, signing, and zipping.
    # It is for local release-candidate review, where launching the app would
    # blur the result by mutating permissions, windows, or user defaults while
    # the artifact is being inspected.
    rm -f "$PACKAGE_ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$PACKAGE_ZIP"
    printf '%s\n' "$PACKAGE_ZIP"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--package]" >&2
    exit 2
    ;;
esac
