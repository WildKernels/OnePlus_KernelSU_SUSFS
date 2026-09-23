#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NH_PACKAGE_ROOT="${NH_PACKAGE_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"
source "$NH_PACKAGE_ROOT/framework/nh-state.sh"
source "$NH_PACKAGE_ROOT/framework/nh-runtime.sh"
source "$NH_PACKAGE_ROOT/framework/nh-fingerprint.sh"

RADIO=bt
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
NH_LOCK_DIR="${NH_LOCK_DIR:-$NH_STATE_DIR}"
VHCI_KO="$NH_PACKAGE_ROOT/vendor_dlkm_override/hci_vhci.ko"
VHCI_NODE="${NH_VHCI_NODE:-/dev/vhci}"
BLUEBINDER="$NH_PACKAGE_ROOT/system/bin/bluebinder"
MODULE_PROP="$NH_PACKAGE_ROOT/module.prop"

log() { nh_log "$RADIO" "$*"; }

restore_android_bt() {
  local enabled rfkill_state
  enabled=$(nh_snapshot_get "$RADIO" bt_enabled 2>/dev/null || echo 1)
  rfkill_state=$(nh_snapshot_get "$RADIO" rfkill_state 2>/dev/null || echo unknown)
  case "$rfkill_state" in
    blocked) rfkill block bluetooth 2>/dev/null || true ;;
    unblocked) rfkill unblock bluetooth 2>/dev/null || true ;;
  esac
  if [ "$enabled" = 1 ]; then
    svc bluetooth enable 2>/dev/null || true
  else
    svc bluetooth disable 2>/dev/null || true
  fi
}

touched_services=0
vhci_loaded=0
bluebinder_started=0

rollback() {
  local reason="$1"
  log "ROLLBACK: $reason"
  if [ "$bluebinder_started" = 1 ]; then
    if [ -f "$NH_STATE_DIR/bluebinder.pid" ]; then
      kill "$(cat "$NH_STATE_DIR/bluebinder.pid")" 2>/dev/null || true
      rm -f "$NH_STATE_DIR/bluebinder.pid"
    fi
    bluebinder_started=0
  fi
  if [ "$vhci_loaded" = 1 ]; then
    rmmod hci_vhci 2>/dev/null || true
    vhci_loaded=0
  fi
  if [ "$touched_services" = 1 ]; then
    restore_android_bt
    touched_services=0
  fi
  if nh_recover_verify "$RADIO" >/dev/null 2>&1; then
    nh_finish_session "$RADIO"
    log "ABORT: $reason (Android restored)"
  else
    nh_mark_recovery_required "$RADIO" "$reason; rollback verification failed"
    log "RECOVERY_REQUIRED: rollback verification failed"
  fi
  exit 1
}

if result=$(nh_check_fingerprint "$MODULE_PROP" btvhci "$VHCI_KO"); then
  :
else
  echo "ABORT: $result" >&2
  exit 1
fi
[ -x "$BLUEBINDER" ] || { echo "ABORT: bluebinder not found at $BLUEBINDER" >&2; exit 1; }

nh_begin_session "$RADIO" || { echo "ABORT: cannot begin session" >&2; exit 1; }
log "Acquiring Bluetooth"

if nh_is_enabled bt; then bt_enabled=1; else bt_enabled=0; fi
hal_state=$(nh_bt_hal_state)
rfkill_state=$(nh_bt_rfkill_state)
nh_snapshot_put "$RADIO" bt_enabled "$bt_enabled"
nh_snapshot_put "$RADIO" hal_state "$hal_state"
nh_snapshot_put "$RADIO" rfkill_state "$rfkill_state"
case "$hal_state:$rfkill_state" in
  running:blocked|running:unblocked|stopped:blocked|stopped:unblocked) ;;
  *) nh_finish_session "$RADIO"; echo "ABORT: Bluetooth HAL or rfkill state is unknown" >&2; exit 1 ;;
esac

touched_services=1
svc bluetooth disable 2>/dev/null || true
sleep 2
rfkill block bluetooth 2>/dev/null || true

insmod "$VHCI_KO" || rollback "insmod hci_vhci failed"
vhci_loaded=1
[ -e "$VHCI_NODE" ] || rollback "/dev/vhci did not appear"

"$BLUEBINDER" --hci 0 </dev/null >/dev/null 2>&1 &
echo $! > "$NH_STATE_DIR/bluebinder.pid"
bluebinder_started=1

i=1
while [ "$i" -le 10 ]; do
  hciconfig hci0 >/dev/null 2>&1 && break
  sleep 1
  i=$((i + 1))
done
hciconfig hci0 >/dev/null 2>&1 || rollback "hci0 did not appear within 10s"
hciconfig hci0 up || rollback "hci0 could not be brought up"

nh_mark_takeover "$RADIO" || rollback "could not mark Bluetooth takeover"
log "TAKEOVER active"
echo "Bluetooth takeover active. hci0 ready."
