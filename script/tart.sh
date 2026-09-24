#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${TART_VM_NAME:-docking-dev}"
IMAGE="${TART_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-xcode:latest}"
CPU="${TART_CPU:-8}"
MEMORY_MB="${TART_MEMORY_MB:-16384}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUEST_ROOT="/Volumes/My Shared Files/docking"
LOG_FILE="${TMPDIR:-/tmp}/docking-tart.log"

usage() {
  cat <<'USAGE'
Usage: ./script/tart.sh <command> [args]

Commands:
  setup       Clone and size the macOS 26 + Xcode development VM.
  start       Start the VM headlessly with this repository mounted.
  gui         Run the VM with a window for manual UI inspection.
  stop        Stop the VM.
  status      Show local Tart VM status.
  shell       Open an interactive shell in the mounted repository.
  exec CMD    Run CMD in the mounted repository.
  doctor      Print guest macOS, Xcode, and Swift versions.
  build       Build Docking in the guest.
  validate    Run DockingValidation and unit tests in the guest.
  check       Build, validate, and run unit tests in the guest.
  verify      Build, stage, launch, and verify Docking in the guest.
  smoke       Run the launch smoke check in the guest.
  release     Run the local release gate in the guest.

Environment overrides:
  TART_VM_NAME     VM name (default: docking-dev)
  TART_IMAGE       Base image (default: macOS Tahoe Xcode latest)
  TART_CPU         Guest CPU count (default: 8)
  TART_MEMORY_MB   Guest memory in MiB (default: 16384)
USAGE
}

require_tart() {
  if ! command -v tart >/dev/null 2>&1; then
    echo "Tart is not installed. Install it with: brew install openai/tools/tart" >&2
    exit 1
  fi

  if [[ "$(uname -m)" != "arm64" ]]; then
    echo "Tart requires an Apple Silicon Mac." >&2
    exit 1
  fi
}

vm_exists() {
  tart list --source local --quiet | grep -Fxq "$VM_NAME"
}

vm_ready() {
  tart exec "$VM_NAME" /usr/bin/true >/dev/null 2>&1
}

repo_mounted() {
  tart exec "$VM_NAME" /bin/test -d "$GUEST_ROOT" >/dev/null 2>&1
}

require_vm() {
  if ! vm_exists; then
    echo "VM '$VM_NAME' does not exist. Run ./script/tart.sh setup first." >&2
    exit 1
  fi
}

setup_vm() {
  require_tart

  if ! vm_exists; then
    echo "Cloning $IMAGE as $VM_NAME..."
    tart clone "$IMAGE" "$VM_NAME"
  else
    echo "Using existing VM '$VM_NAME'."
  fi

  tart set "$VM_NAME" --cpu "$CPU" --memory "$MEMORY_MB"
  echo "Configured $VM_NAME with $CPU CPUs and ${MEMORY_MB} MiB memory."
}

start_vm() {
  require_tart
  require_vm

  if vm_ready; then
    if repo_mounted; then
      return
    fi

    echo "VM '$VM_NAME' is running without the Docking source mount." >&2
    echo "Stop it and restart it with ./script/tart.sh start." >&2
    exit 1
  fi

  rm -f "$LOG_FILE"
  nohup tart run --no-graphics --dir="docking:$ROOT_DIR" "$VM_NAME" >"$LOG_FILE" 2>&1 &
  local tart_pid=$!

  for _ in {1..120}; do
    if vm_ready; then
      if repo_mounted; then
        echo "Started $VM_NAME."
        return
      fi

      echo "Guest started, but the Docking source mount is unavailable." >&2
      exit 1
    fi

    if ! kill -0 "$tart_pid" >/dev/null 2>&1; then
      echo "Tart exited before the guest became ready. Log: $LOG_FILE" >&2
      tail -n 20 "$LOG_FILE" >&2 || true
      exit 1
    fi

    sleep 1
  done

  echo "Timed out waiting for $VM_NAME. Log: $LOG_FILE" >&2
  exit 1
}

guest() {
  local command="$1"
  start_vm
  tart exec "$VM_NAME" /bin/zsh -lc "cd '$GUEST_ROOT' && $command"
}

# The guest's AppleVirtIOFS client does not revalidate its caches when the host
# changes a file: a file replaced by rename keeps resolving to the deleted inode,
# and an in-place rewrite shows the new size and mtime with the old bytes. SwiftPM
# then skips or recompiles from stale sources and the check still passes. A
# remount drops those caches. Docking is stopped first because a launched
# dist/Docking.app keeps the mount busy, and diskutil is used instead of umount
# because Spotlight's mds holds the volume root open after a launch.
guest_with_fresh_mount() {
  local command="$1"
  local mount_point="${GUEST_ROOT%/*}"
  start_vm
  if ! tart exec "$VM_NAME" /bin/zsh -c "
    /usr/bin/pkill -x Docking
    for _ in {1..50}; do /usr/bin/pgrep -x Docking >/dev/null || break; sleep 0.1; done
    sudo -n /usr/sbin/diskutil quiet unmount '$mount_point' &&
      sudo -n /bin/mkdir -p '$mount_point' &&
      sudo -n /sbin/mount_virtiofs com.apple.virtio-fs.automount '$mount_point' &&
      /bin/test -d '$GUEST_ROOT'
  "; then
    echo "Could not remount '$mount_point' in $VM_NAME to drop stale host file caches." >&2
    echo "Close guest shells or processes using the mount, or restart the VM with ./script/tart.sh stop." >&2
    exit 1
  fi
  guest "$command"
}

run_gui() {
  require_tart
  require_vm

  if vm_ready; then
    echo "VM '$VM_NAME' is already running. Stop it before starting GUI mode." >&2
    exit 1
  fi

  exec tart run --dir="docking:$ROOT_DIR" "$VM_NAME"
}

command="${1:-}"
case "$command" in
  setup)
    setup_vm
    ;;
  start)
    start_vm
    ;;
  gui)
    run_gui
    ;;
  stop)
    require_tart
    require_vm
    tart stop "$VM_NAME"
    ;;
  status)
    require_tart
    tart list --source local
    ;;
  shell)
    start_vm
    tart exec -i -t "$VM_NAME" /bin/zsh -lc "cd '$GUEST_ROOT' && exec /bin/zsh -l"
    ;;
  exec)
    shift
    if [[ $# -eq 0 ]]; then
      echo "exec requires a command." >&2
      exit 2
    fi
    guest "$*"
    ;;
  doctor)
    guest "sw_vers && printf '\\n' && xcodebuild -version && printf '\\n' && swift --version"
    ;;
  build)
    guest_with_fresh_mount "swift build --product Docking --scratch-path /private/tmp/docking-app-swiftpm-run"
    ;;
  validate)
    guest_with_fresh_mount "swift run --scratch-path /private/tmp/docking-validation DockingValidation && swift test --scratch-path /private/tmp/docking-validation"
    ;;
  check)
    guest_with_fresh_mount "swift build --product Docking --scratch-path /private/tmp/docking-app-swiftpm-run && swift run --scratch-path /private/tmp/docking-validation DockingValidation && swift test --scratch-path /private/tmp/docking-validation"
    ;;
  verify)
    guest_with_fresh_mount "./script/build_and_run.sh --verify"
    ;;
  smoke)
    guest_with_fresh_mount "./script/launch_smoke_check.sh"
    ;;
  release)
    guest_with_fresh_mount "./script/release_check.sh"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $command" >&2
    usage >&2
    exit 2
    ;;
esac
