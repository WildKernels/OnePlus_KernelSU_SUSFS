#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NH_PACKAGE_ROOT="${NH_PACKAGE_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"
source "$NH_PACKAGE_ROOT/framework/nh-state.sh"
source "$NH_PACKAGE_ROOT/framework/nh-runtime.sh"

RADIO=bt
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
NH_LOCK_DIR="${NH_LOCK_DIR:-$NH_STATE_DIR}"

log() { nh_log "$RADIO" "$*"; }

state=$(nh_get_state "$RADIO")
if [ "$state" = IDLE ] || [ "$state" = BOOT_RECOVERED ]; then
  echo "Bluetooth already in stock state."
  exit 0
fi
if [ "$state" != TAKEOVER ] && { [ "$state" != RECOVERY_REQUIRED ] || [ "${NH_RECOVERY_MODE:-0}" != 1 ]; }; then
  echo "Bluetooth is in $state; use nh-recover (journal kept)." >&2
  exit 1
fi

log "Releasing Bluetooth"
nh_set_state "$RADIO" RESTORE

if [ -f "$NH_STATE_DIR/bluebinder.pid" ]; then
  BPID=$(cat "$NH_STATE_DIR/bluebinder.pid")
  case "$BPID" in
    ''|*[!0-9]*)
      nh_mark_recovery_required "$RADIO" "invalid bluebinder PID file"
      echo "ERROR: invalid bluebinder PID file; journal retained" >&2
      exit 1
      ;;
  esac
  kill "$BPID" 2>/dev/null || true
  sleep 1
  if kill -0 "$BPID" 2>/dev/null; then
    kill -9 "$BPID" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$NH_STATE_DIR/bluebinder.pid"
fi

hciconfig hci0 down 2>/dev/null || true
rmmod hci_vhci 2>/dev/null || true

rfkill_state=$(nh_snapshot_get "$RADIO" rfkill_state 2>/dev/null || echo unknown)
case "$rfkill_state" in
  blocked) rfkill block bluetooth 2>/dev/null || true ;;
  unblocked) rfkill unblock bluetooth 2>/dev/null || true ;;
  *) nh_mark_recovery_required "$RADIO" "saved rfkill state is unknown"; exit 1 ;;
esac

bt_enabled=$(nh_snapshot_get "$RADIO" bt_enabled 2>/dev/null || echo 1)
if [ "$bt_enabled" = 1 ]; then
  svc bluetooth enable 2>/dev/null || true
else
  svc bluetooth disable 2>/dev/null || true
fi

sleep 2
if ! nh_recover_verify "$RADIO" >/dev/null 2>&1; then
  log "RECOVERY_REQUIRED: stock Bluetooth verification failed"
  nh_mark_recovery_required "$RADIO" "stock Bluetooth verification failed on release"
  echo "ERROR: Bluetooth restore could not be verified; journal retained" >&2
  exit 1
fi

nh_finish_session "$RADIO"
log "RESTORED to stock"
echo "Bluetooth restored to stock."
