#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/../framework/nh-state.sh"

RADIO="nfc"
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
LOG="$NH_STATE_DIR/nfc.log"

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }

state=$(nh_get_state "$RADIO")
if [ "$state" = "IDLE" ]; then
  echo "NFC already in stock state."
  exit 0
fi
if [ "$state" != "TAKEOVER" ]; then
  echo "NFC is in $state; manual recovery required (journal kept)." >&2
  exit 1
fi

log "Releasing NFC"

# Restore to the pre-takeover snapshot, not blindly on
nfc_enabled=$(nh_snapshot_get "$RADIO" nfc_enabled 2>/dev/null || echo 1)

start vendor.nfc_hal_service 2>/dev/null || true
sleep 2
if [ "$nfc_enabled" = "1" ]; then
  svc nfc enable 2>/dev/null || true
  cmd nfc enable-nfc 2>/dev/null || true
fi

# Verify Android actually got NFC back before clearing the journal
sleep 2
if [ "$nfc_enabled" = "1" ]; then
  if ! dumpsys nfc 2>/dev/null | grep -q 'mState=on'; then
    log "RECOVERY_REQUIRED: NFC mState not on after restore"
    nh_mark_recovery_required "$RADIO" "NFC not operational after restore"
    echo "ERROR: NFC did not come back; manual recovery required" >&2
    exit 1
  fi
else
  if dumpsys nfc 2>/dev/null | grep -q 'mState=on'; then
    log "RECOVERY_REQUIRED: NFC unexpectedly on after restore (was off)"
    nh_mark_recovery_required "$RADIO" "NFC unexpectedly on after restore"
    echo "ERROR: NFC restored to wrong state; manual recovery required" >&2
    exit 1
  fi
fi

nh_finish_session "$RADIO"
log "RESTORED to stock"
echo "NFC restored to stock."
