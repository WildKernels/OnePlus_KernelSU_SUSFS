#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/../framework/nh-state.sh"

RADIO="nfc"
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
NH_MODULE_DIR="${NH_MODULE_DIR:-/data/adb/modules/nethunter_takeover}"
NCI_TOOL="$NH_MODULE_DIR/system/bin/nci_raw_tool"
LOG="$NH_STATE_DIR/nfc.log"

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }

touched_services=0

rollback() {
  reason="$1"
  log "ROLLBACK: $reason"
  if [ "$touched_services" = 1 ]; then
    start vendor.nfc_hal_service 2>/dev/null || true
    svc nfc enable 2>/dev/null || true
    touched_services=0
  fi
  nh_finish_session "$RADIO"
  log "ABORT: $reason (Android restored)"
  exit 1
}

# Gate: nci_raw_tool must exist and run before we touch anything
if [ ! -x "$NCI_TOOL" ]; then
  echo "ABORT: nci_raw_tool not found at $NCI_TOOL" >&2
  exit 1
fi
"$NCI_TOOL" probe >/dev/null 2>&1 || { echo "ABORT: nci_raw_tool probe failed" >&2; exit 1; }

nh_begin_session "$RADIO" || { echo "ABORT: cannot begin session" >&2; exit 1; }
log "Acquiring NFC"

# Snapshot pre-state
if dumpsys nfc 2>/dev/null | grep -q 'mState=on'; then
  nh_snapshot_put "$RADIO" nfc_enabled 1
else
  nh_snapshot_put "$RADIO" nfc_enabled 0
fi
nh_snapshot_put "$RADIO" hal_state "$(getprop init.svc.vendor.nfc_hal_service 2>/dev/null || echo unknown)"

# Quiesce Android NFC so the NCI device is free
cmd nfc disable-nfc persist 2>/dev/null || true
svc nfc disable 2>/dev/null || true
sleep 2
stop vendor.nfc_hal_service 2>/dev/null || true
touched_services=1
sleep 2

# Smoke test: NCI reset + init handshake
"$NCI_TOOL" init || rollback "nci_raw_tool init failed"

nh_mark_takeover "$RADIO"
log "TAKEOVER active"
echo "NFC takeover active. /dev/nq-nci free for NetHunter use."
