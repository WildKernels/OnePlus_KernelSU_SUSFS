#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/../framework/nh-state.sh"
source "$SCRIPT_DIR/../framework/nh-fingerprint.sh"

RADIO="bt"
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
NH_MODULE_DIR="${NH_MODULE_DIR:-/data/adb/modules/nethunter_takeover}"
VHCI_KO="$NH_MODULE_DIR/vendor_dlkm_override/hci_vhci.ko"
BLUEBINDER="$NH_MODULE_DIR/system/bin/bluebinder"
LOG="$NH_STATE_DIR/bt.log"

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }

touched_services=0
vhci_loaded=0
bluebinder_started=0

rollback() {
  reason="$1"
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
    rfkill unblock bluetooth 2>/dev/null || true
    svc bluetooth enable 2>/dev/null || true
    touched_services=0
  fi
  nh_finish_session "$RADIO"
  log "ABORT: $reason (Android restored)"
  exit 1
}

# Gate: fingerprint + patched module integrity, before touching anything
result=$(nh_check_fingerprint "$NH_MODULE_DIR/module.prop" "btvhci" "$VHCI_KO")
if [ "$result" != "OK" ]; then
  echo "ABORT: $result" >&2
  exit 1
fi

nh_begin_session "$RADIO" || { echo "ABORT: cannot begin session" >&2; exit 1; }
log "Acquiring Bluetooth"

# Snapshot pre-state
if dumpsys bluetooth_manager 2>/dev/null | grep -q -e 'state: ON' -e 'Bluetooth is enabled'; then
  nh_snapshot_put "$RADIO" bt_enabled 1
else
  nh_snapshot_put "$RADIO" bt_enabled 0
fi
nh_snapshot_put "$RADIO" hal_state "$(getprop init.svc.bluetooth 2>/dev/null || getprop init.svc.vendor.bluetooth 2>/dev/null || echo unknown)"

# Quiesce Android Bluetooth
svc bluetooth disable 2>/dev/null || true
sleep 3
rfkill block bluetooth 2>/dev/null || true
touched_services=1
sleep 1

# Load the VHCI module built from the same kernel tree
insmod "$VHCI_KO" || rollback "insmod hci_vhci failed"
vhci_loaded=1

# Start bluebinder daemon bridging the VHCI to a userspace hci
"$BLUEBINDER" --hci 0 </dev/null >/dev/null 2>&1 &
echo $! > "$NH_STATE_DIR/bluebinder.pid"
bluebinder_started=1

# Wait for hci0 (10s timeout)
i=1
while [ $i -le 10 ]; do
  if hciconfig hci0 >/dev/null 2>&1; then
    break
  fi
  sleep 1
  i=$((i + 1))
done

hciconfig hci0 >/dev/null 2>&1 || rollback "hci0 did not appear within 10s"

hciconfig hci0 up
nh_mark_takeover "$RADIO"
log "TAKEOVER active"
echo "Bluetooth takeover active. hci0 ready."
