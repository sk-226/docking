#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Docking"
BUNDLE_ID="app.docking.docking"
APP_VERSION="0.0.0"
MIN_SYSTEM_VERSION="26.0"
CALENDAR_USAGE_DESCRIPTION="Docking shows your upcoming events in the calendar widget."
CALENDAR_FULL_ACCESS_DESCRIPTION="Docking needs full calendar access to read upcoming events for the calendar widget."
LOCATION_USAGE_DESCRIPTION="Docking can use your location for the weather widget when you enable current-location weather."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
PACKAGE_ZIP="$DIST_DIR/$APP_NAME-$APP_VERSION-macos26.zip"
PACKAGE_SHA256_FILE="$PACKAGE_ZIP.sha256"
PACKAGE_DMG="$DIST_DIR/$APP_NAME-$APP_VERSION-macos26.dmg"
PACKAGE_DMG_SHA256_FILE="$PACKAGE_DMG.sha256"
DMG_VOLUME_NAME="$APP_NAME $APP_VERSION"
APP_ICON="$APP_BUNDLE/Contents/Resources/DockingAppIcon.icns"
MENU_BAR_ICON="$APP_BUNDLE/Contents/Resources/DockingMenuBarTemplate.png"
EMBEDDED_PROFILE="$APP_BUNDLE/Contents/embedded.provisionprofile"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
MOCK_WEATHER_PROVIDER="$ROOT_DIR/Sources/DockingCore/Widgets/Weather/MockWeatherProvider.swift"

cd "$ROOT_DIR"

TEMP_PATHS=()
DMG_ATTACHED_MOUNT=""

cleanup_release_check() {
  if [[ -n "${DMG_ATTACHED_MOUNT:-}" ]]; then
    /usr/bin/hdiutil detach "$DMG_ATTACHED_MOUNT" >/dev/null 2>&1 || true
  fi
  if ((${#TEMP_PATHS[@]})); then
    rm -rf "${TEMP_PATHS[@]}"
  fi
  if [[ -n "${ENTITLEMENTS_DUMP:-}" ]]; then
    rm -f "$ENTITLEMENTS_DUMP"
  fi
}

trap cleanup_release_check EXIT

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

assert_permission_description() {
  local key="$1"
  local expected="$2"

  # Permission prompts are part of the product safety contract, not incidental
  # bundle metadata. macOS will show these strings before users trust Docking
  # with Calendar or Location access, so a missing or generic placeholder should
  # fail the release gate just like a wrong bundle identifier. Checking the
  # exact local text is intentionally stricter than "non-empty": for a 0.0.0
  # personal app, changing prompt wording should be a deliberate review point,
  # not an unnoticed side effect of touching the build script.
  assert_plist_value "$key" "$expected"
}

fail_if_matches() {
  local description="$1"
  local pattern="$2"
  local status
  shift 2

  if command -v rg >/dev/null 2>&1; then
    # ripgrep is the preferred local path because it respects gitignore-style
    # globs and stays fast as the authored surface grows. We still avoid
    # depending on it as a release prerequisite: GitHub's macOS runners do not
    # guarantee `rg`, and installing tooling during CI would make the release
    # gate depend on Homebrew/network state instead of just the checkout.
    set +e
    rg -n "$pattern" "$@"
    status=$?
    set -e
  else
    local grep_paths=()
    local grep_excludes=("--exclude-dir=.git" "--exclude-dir=.build" "--exclude-dir=dist")

    # The current fallback only needs the small subset of ripgrep's argument
    # shape used by this script: explicit search roots plus negative `-g`
    # excludes. Failing closed on unsupported include globs is intentional; a
    # future release check should not silently broaden or narrow hygiene scans
    # just because CI is using the POSIX tool path.
    while (($#)); do
      case "$1" in
        -g)
          shift
          if [[ $# -eq 0 ]]; then
            printf 'Release check failed: missing glob after -g while checking %s\n' "$description" >&2
            exit 1
          fi
          if [[ "$1" == !* ]]; then
            local excluded="${1#!}"
            case "$excluded" in
              */**)
                excluded="${excluded%/**}"
                grep_excludes+=("--exclude-dir=${excluded##*/}")
                ;;
              */*)
                grep_excludes+=("--exclude=${excluded##*/}")
                ;;
              *)
                grep_excludes+=("--exclude=$excluded")
                ;;
            esac
          else
            printf 'Release check failed: grep fallback does not support include glob %s while checking %s\n' "$1" "$description" >&2
            exit 1
          fi
          ;;
        *)
          grep_paths+=("$1")
          ;;
      esac
      shift
    done

    if ((${#grep_paths[@]} == 0)); then
      grep_paths=(".")
    fi

    set +e
    /usr/bin/grep -R -n -E "${grep_excludes[@]}" -- "$pattern" "${grep_paths[@]}"
    status=$?
    set -e
  fi

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

section "Release app bundle and artifacts"
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
assert_plist_value NSHighResolutionCapable "true"

section "Permission descriptions"
assert_permission_description NSCalendarsUsageDescription "$CALENDAR_USAGE_DESCRIPTION"
assert_permission_description NSCalendarsFullAccessUsageDescription "$CALENDAR_FULL_ACCESS_DESCRIPTION"
assert_permission_description NSLocationWhenInUseUsageDescription "$LOCATION_USAGE_DESCRIPTION"
assert_permission_description NSLocationUsageDescription "$LOCATION_USAGE_DESCRIPTION"

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

section "WeatherKit entitlement mode"
ENTITLEMENTS_DUMP="$(mktemp "${TMPDIR:-/tmp}/docking-entitlements.XXXXXX.plist")"
/usr/bin/codesign -d --entitlements :- "$APP_BUNDLE" >"$ENTITLEMENTS_DUMP" 2>/dev/null || true

if [[ -s "$EMBEDDED_PROFILE" ]]; then
  if ! /usr/bin/grep -q "com.apple.developer.weatherkit" "$ENTITLEMENTS_DUMP"; then
    printf 'Release check failed: embedded profile exists but WeatherKit entitlement was not sealed into %s\n' "$APP_BUNDLE" >&2
    exit 1
  fi
else
  if /usr/bin/grep -q "com.apple.developer.weatherkit" "$ENTITLEMENTS_DUMP"; then
    printf 'Release check failed: WeatherKit entitlement is present without an embedded provisioning profile\n' >&2
    exit 1
  fi
  printf 'WeatherKit entitlement absent; release candidate will use Open-Meteo fallback unless a matching profile is supplied.\n'
fi

section "Source hygiene"
# Keep this check narrow. The release gate should block concrete forbidden
# APIs or OS-version shims, not generic words in comments, docs, or validation
# messages. Broad keyword scans such as "legacy" or "compatibility" create
# false positives and make release_check brittle; legitimate Codable patterns
# such as decodeIfPresent are also not release risks by themselves.
fail_if_matches \
  "forbidden backward-compatibility shims or deprecated permission APIs still appear in authored source" \
  "#available|#unavailable|requestAccess\\(to:" \
  Sources Validation Package.swift script/build_and_run.sh

fail_if_matches \
  "user-specific path or old bundle identifier still appears in authored files" \
  "s[u]gu|/U[s]ers/|com\\.s[u]gu\\.docking" \
  -g '!dist/**' -g '!.git/**' -g '!script/release_check.sh' .

section "Production mock boundary"
# The product requirement is stronger than "real provider exists": production
# builds must not be able to fall back to fake weather. Import lines are allowed
# outside the guard because they do not create a runtime implementation; the
# invariant we actually care about is that the provider type itself remains
# enclosed by DEBUG-only compilation. The release binary check below catches the
# important second half: a source guard typo must not silently ship in the app.
debug_guard_line="$(/usr/bin/awk '/^#if DEBUG$/ { print NR; exit }' "$MOCK_WEATHER_PROVIDER")"
provider_line="$(/usr/bin/awk '/final class MockWeatherProvider/ { print NR; exit }' "$MOCK_WEATHER_PROVIDER")"
endif_line="$(/usr/bin/awk '/^#endif$/ { line=NR } END { if (line) print line }' "$MOCK_WEATHER_PROVIDER")"
if [[ -z "$debug_guard_line" || -z "$provider_line" || -z "$endif_line" ]] ||
  (( debug_guard_line >= provider_line || endif_line <= provider_line )); then
  printf 'Release check failed: MockWeatherProvider.swift must remain DEBUG-only.\n' >&2
  exit 1
fi

if /usr/bin/strings "$APP_BINARY" | /usr/bin/grep -q "MockWeatherProvider"; then
  printf 'Release check failed: release binary still contains MockWeatherProvider.\n' >&2
  exit 1
fi

section "Package"
if [[ ! -s "$PACKAGE_ZIP" ]]; then
  printf 'Release check failed: package was not created at %s\n' "$PACKAGE_ZIP" >&2
  exit 1
fi

# Keep a plain zip as a mechanically simple fallback, but make the DMG the
# tester-facing artifact. A decorative DMG layout would require Finder metadata
# and background assets, which is extra surface area for a 0.0.0 candidate. The
# minimal macOS convention is enough here: the app bundle plus an Applications
# symlink so testers can drag-install without guessing where the app belongs.
DMG_SOURCE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/docking-dmg-source.XXXXXX")"
DMG_MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/docking-dmg-mount.XXXXXX")"
TEMP_PATHS+=("$DMG_SOURCE_DIR" "$DMG_MOUNT_DIR")
/usr/bin/ditto "$APP_BUNDLE" "$DMG_SOURCE_DIR/$APP_NAME.app"
/bin/ln -s /Applications "$DMG_SOURCE_DIR/Applications"
rm -f "$PACKAGE_DMG"
/usr/bin/hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$DMG_SOURCE_DIR" \
  -ov \
  -format UDZO \
  "$PACKAGE_DMG" >/dev/null

if [[ ! -s "$PACKAGE_DMG" ]]; then
  printf 'Release check failed: DMG was not created at %s\n' "$PACKAGE_DMG" >&2
  exit 1
fi

# A valid staged `.app` is not enough if the zip or DMG accidentally contains
# the wrong root, misses resources, or packages a stale file from a previous
# run. Inspect the archives themselves because these are the exact artifacts
# that will be attached to a PR or handed to a tester. We check only the stable
# bundle contract here; enumerating every file would make harmless Swift
# compiler layout changes look like release failures.
ZIP_LIST="$(/usr/bin/unzip -Z -1 "$PACKAGE_ZIP")"
for archived_path in \
  "$APP_NAME.app/Contents/Info.plist" \
  "$APP_NAME.app/Contents/MacOS/$APP_NAME" \
  "$APP_NAME.app/Contents/Resources/DockingAppIcon.icns" \
  "$APP_NAME.app/Contents/Resources/DockingMenuBarTemplate.png"; do
  if ! /usr/bin/grep -qx "$archived_path" <<<"$ZIP_LIST"; then
    printf 'Release check failed: package is missing %s\n' "$archived_path" >&2
    exit 1
  fi
done

/usr/bin/hdiutil imageinfo -plist "$PACKAGE_DMG" >/dev/null
DMG_ATTACHED_MOUNT="$DMG_MOUNT_DIR"
/usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "$DMG_MOUNT_DIR" "$PACKAGE_DMG" >/dev/null
DMG_LIST="$(/usr/bin/find "$DMG_MOUNT_DIR" -maxdepth 4 -print)"
/usr/bin/hdiutil detach "$DMG_MOUNT_DIR" >/dev/null
DMG_ATTACHED_MOUNT=""
for dmg_path in \
  "$DMG_MOUNT_DIR/$APP_NAME.app/Contents/Info.plist" \
  "$DMG_MOUNT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" \
  "$DMG_MOUNT_DIR/$APP_NAME.app/Contents/Resources/DockingAppIcon.icns" \
  "$DMG_MOUNT_DIR/$APP_NAME.app/Contents/Resources/DockingMenuBarTemplate.png" \
  "$DMG_MOUNT_DIR/Applications"; do
  if ! /usr/bin/grep -qx "$dmg_path" <<<"$DMG_LIST"; then
    printf 'Release check failed: DMG is missing %s\n' "${dmg_path#"$DMG_MOUNT_DIR/"}" >&2
    exit 1
  fi
done

printf 'Release candidate package: %s\n' "$PACKAGE_ZIP"
printf 'Release candidate DMG: %s\n' "$PACKAGE_DMG"

section "Release identity"
# The release artifacts can be reviewed later, attached to a draft PR, or
# compared against a user-tested build. Printing branch, commit, cleanliness,
# and checksums here gives those artifacts a durable identity without forcing a
# git push or changing local branch policy. We intentionally report a dirty tree
# instead of failing: during active 0.0.0 UI work, the script is also useful as
# a pre-commit gate, while the PR template and QA checklist still require a
# clean tree before handoff.
GIT_BRANCH="$(git branch --show-current 2>/dev/null || true)"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || true)"
GIT_STATUS="$(git status --short 2>/dev/null || true)"
PACKAGE_SHA256="$(/usr/bin/shasum -a 256 "$PACKAGE_ZIP" | /usr/bin/awk '{print $1}')"
DMG_SHA256="$(/usr/bin/shasum -a 256 "$PACKAGE_DMG" | /usr/bin/awk '{print $1}')"
# Keep checksums beside the artifacts so they can be verified even after this
# terminal scrollback is gone. We intentionally write standard two-column shasum
# files rather than inventing a JSON manifest: the 0.0.0 release surface needs
# to stay simple, and `shasum -c` can consume this format directly.
printf '%s  %s\n' "$PACKAGE_SHA256" "${PACKAGE_ZIP##*/}" >"$PACKAGE_SHA256_FILE"
printf '%s  %s\n' "$DMG_SHA256" "${PACKAGE_DMG##*/}" >"$PACKAGE_DMG_SHA256_FILE"
(
  cd "$DIST_DIR"
  /usr/bin/shasum -c "${PACKAGE_SHA256_FILE##*/}"
  /usr/bin/shasum -c "${PACKAGE_DMG_SHA256_FILE##*/}"
)

printf 'Branch: %s\n' "${GIT_BRANCH:-unknown}"
printf 'Commit: %s\n' "${GIT_COMMIT:-unknown}"
printf 'Package SHA-256: %s\n' "$PACKAGE_SHA256"
printf 'DMG SHA-256: %s\n' "$DMG_SHA256"
printf 'Checksum file: %s\n' "$PACKAGE_SHA256_FILE"
printf 'DMG checksum file: %s\n' "$PACKAGE_DMG_SHA256_FILE"
if [[ -n "$GIT_STATUS" ]]; then
  printf 'Git status: dirty worktree; review before GitHub handoff.\n'
else
  printf 'Git status: clean worktree.\n'
fi
