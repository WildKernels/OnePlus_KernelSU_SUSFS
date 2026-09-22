#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/../framework/nh-state.sh"

RADIO="bt"
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
LOG="$NH_STATE_DIR/bt.log"

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }

state=$(nh_get_state "$RADIO")
if [ "$state" = "IDLE" ]; then
  echo "Bluetooth already in stock state."
  exit 0
fi
if [ "$state" != "TAKEOVER" ]; then
  echo "Bluetooth is in $state; manual recovery required (journal kept)." >&2
  exit 1
fi

log "Releasing Bluetooth"

# Stop bluebinder first so nothing feeds the VHCI during teardown
if [ -f "$NH_STATE_DIR/bluebinder.pid" ]; then
  BPID="$(cat "$NH_STATE_DIR/bluebinder.pid")"
  kill "$BPID" 2>/dev/null || true
  sleep 1
  if kill -0 "$BPID" 2>/dev/null; then
    log "WARN: bluebinder ($BPID) still alive, sending SIGKILL"
    kill -9 "$BPID" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$NH_STATE_DIR/bluebinder.pid"
fi

hciconfig hci0 down 2>/dev/null || true
rmmod hci_vhci 2>/dev/null || true

# Restore Bluetooth to its pre-takeover state, not blindly enabled
bt_enabled=$(nh_snapshot_get "$RADIO" bt_enabled 2>/dev/null || echo 1)
rfkill unblock bluetooth 2>/dev/null || true
if [ "$bt_enabled" = "1" ]; then
  svc bluetooth enable 2>/dev/null || true
fi

# Verify Android actually got Bluetooth back before clearing the journal
sleep 2
if [ "$bt_enabled" = "1" ]; then
  if ! dumpsys bluetooth_manager 2>/dev/null | grep -q -e 'state: ON' -e 'Bluetooth is enabled'; then
    log "RECOVERY_REQUIRED: Android Bluetooth not operational after restore"
    nh_mark_recovery_required "$RADIO" "Android Bluetooth not operational after restore"
    echo "ERROR: Bluetooth did not come back; manual recovery required" >&2
    exit 1
  fi
else
  if dumpsys bluetooth_manager 2>/dev/null | grep -q -e 'state: ON' -e 'Bluetooth is enabled'; then
    log "RECOVERY_REQUIRED: Bluetooth unexpectedly ON after restore (was off)"
    nh_mark_recovery_required "$RADIO" "Bluetooth unexpectedly on after restore"
    echo "ERROR: Bluetooth restored to wrong state; manual recovery required" >&2
    exit 1
  fi
fi

nh_finish_session "$RADIO"
log "RESTORED to stock"
echo "Bluetooth restored to stock."
