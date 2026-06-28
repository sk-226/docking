#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Docking"
BUNDLE_ID="app.docking.docking"
APP_VERSION="0.0.0"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
PACKAGE_ZIP="$DIST_DIR/$APP_NAME-$APP_VERSION-macos26.zip"
APP_ICON="$APP_BUNDLE/Contents/Resources/DockingAppIcon.icns"
MENU_BAR_ICON="$APP_BUNDLE/Contents/Resources/DockingMenuBarTemplate.png"

cd "$ROOT_DIR"

section() {
  printf '\n==> %s\n' "$1"
}

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual

  actual="$(/usr/libexec/PlistBuddy -c "Print:$key" "$INFO_PLIST")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Release check failed: %s expected %s, got %s\n' "$key" "$expected" "$actual" >&2
    exit 1
  fi
}

fail_if_matches() {
  local description="$1"
  local status
  shift

  # ripgrep uses 1 for "no matches" and 2+ for real search errors. Treating all
  # non-zero exits as success would make this gate look green when a path typo or
  # missing tool prevented the check from running, so handle the statuses
  # explicitly instead of relying on the usual `if rg ...` shortcut.
  set +e
  rg -n "$@"
  status=$?
  set -e

  case "$status" in
    0)
      printf 'Release check failed: %s\n' "$description" >&2
      exit 1
      ;;
    1)
      return 0
      ;;
    *)
      printf 'Release check failed: search command errored while checking %s\n' "$description" >&2
      exit "$status"
      ;;
  esac
}

section "Validation executable"
swift run --scratch-path /private/tmp/docking-app-swiftpm-validation DockingValidation

section "Release app bundle and zip"
# The release artifact must be built through the same app-bundle staging script
# that developers run every day. A separate release-only packager would look
# cleaner at first, but it would let Info.plist keys, permission usage strings,
# and signing behavior drift from the app users actually test.
CONFIGURATION=release SWIFTPM_SCRATCH_PATH=/private/tmp/docking-app-swiftpm-release-package \
  "$ROOT_DIR/script/build_and_run.sh" --package

section "Bundle metadata"
assert_plist_value CFBundleShortVersionString "$APP_VERSION"
assert_plist_value CFBundleVersion "$APP_VERSION"
assert_plist_value CFBundleIdentifier "$BUNDLE_ID"
assert_plist_value CFBundleIconFile "DockingAppIcon"
assert_plist_value LSMinimumSystemVersion "$MIN_SYSTEM_VERSION"

if [[ ! -s "$APP_ICON" || ! -s "$MENU_BAR_ICON" ]]; then
  printf 'Release check failed: icon resources were not copied into %s\n' "$APP_BUNDLE" >&2
  exit 1
fi

section "Code signature"
# This is a local signature-integrity gate, not a notarization claim. Developer
# ID signing, hardened runtime, and notarization need distribution credentials
# and should remain an explicit follow-up instead of being silently approximated
# by a 0.0.0 local candidate.
/usr/bin/codesign --verify --deep --verbose=2 "$APP_BUNDLE"

section "Source hygiene"
fail_if_matches \
  "old compatibility or deprecated-access code still appears in authored source" \
  "#available|backward|compatib|decodeIfPresent|legacy|deprecated|requestAccess\\(to:" \
  Sources Validation README.md PERFORMANCE.md Package.swift script/build_and_run.sh

fail_if_matches \
  "user-specific path or old bundle identifier still appears in authored files" \
  "s[u]gu|/U[s]ers/|com\\.s[u]gu\\.docking" \
  -g '!dist/**' -g '!.git/**' -g '!script/release_check.sh' .

section "Package"
if [[ ! -s "$PACKAGE_ZIP" ]]; then
  printf 'Release check failed: package was not created at %s\n' "$PACKAGE_ZIP" >&2
  exit 1
fi

printf 'Release candidate package: %s\n' "$PACKAGE_ZIP"
