#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/../framework/nh-state.sh"

RADIO="wifi"
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
STOCK_KO="${NH_VENDOR_KO:-/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko}"
LOG="$NH_STATE_DIR/wifi.log"

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }

state=$(nh_get_state "$RADIO")
if [ "$state" = "IDLE" ]; then
  echo "Wi-Fi already in stock state."
  exit 0
fi
if [ "$state" != "TAKEOVER" ]; then
  echo "Wi-Fi is in $state; manual recovery required (journal kept)." >&2
  exit 1
fi

log "Releasing Wi-Fi"

iw dev mon0 del 2>/dev/null || true
rmmod qca_cld3_kiwi_v2 2>/dev/null || true

if ! insmod "$STOCK_KO" 2>/dev/null; then
  log "RECOVERY_REQUIRED: stock module reload failed"
  nh_mark_recovery_required "$RADIO" "stock module insmod failed on release"
  echo "ERROR: stock module reload failed; Android Wi-Fi needs manual recovery" >&2
  exit 1
fi

start vendor.wifi_hal_legacy 2>/dev/null || true
sleep 2
svc wifi enable 2>/dev/null || true

# Verify Android actually got Wi-Fi back before clearing the journal
sleep 2
if ! dumpsys wifi 2>/dev/null | grep -q 'Wi-Fi is operational'; then
  log "RECOVERY_REQUIRED: dumpsys wifi not operational after restore"
  nh_mark_recovery_required "$RADIO" "Android Wi-Fi not operational after restore"
  echo "ERROR: Wi-Fi did not come back; manual recovery required" >&2
  exit 1
fi

nh_finish_session "$RADIO"
log "RESTORED to stock"
echo "Wi-Fi restored to stock."
