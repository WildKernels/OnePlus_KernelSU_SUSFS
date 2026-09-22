#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/../framework/nh-state.sh"
source "$SCRIPT_DIR/../framework/nh-fingerprint.sh"

RADIO="wifi"
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
NH_MODULE_DIR="${NH_MODULE_DIR:-/data/adb/modules/nethunter_takeover}"
STOCK_KO="${NH_VENDOR_KO:-/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko}"
KO_PATH="$NH_MODULE_DIR/vendor_dlkm_override/qca_cld3_kiwi_v2.ko"
MODULE_PROP="$NH_MODULE_DIR/module.prop"
LOG="$NH_STATE_DIR/wifi.log"

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }

touched_services=0
stock_unloaded=0
patched_loaded=0

# Full rollback: restore Android ownership exactly as found. Only a failed
# rollback keeps RECOVERY_REQUIRED; successful rollback cleans the session.
rollback() {
  reason="$1"
  log "ROLLBACK: $reason"
  if [ "$patched_loaded" = 1 ]; then
    rmmod qca_cld3_kiwi_v2 2>/dev/null || true
    patched_loaded=0
  fi
  if [ "$stock_unloaded" = 1 ]; then
    insmod "$STOCK_KO" 2>/dev/null || { nh_mark_recovery_required "$RADIO" "$reason; stock insmod also failed"; log "RECOVERY_REQUIRED: stock module could not be reloaded"; exit 1; }
    stock_unloaded=0
  fi
  if [ "$touched_services" = 1 ]; then
    start vendor.wifi_hal_legacy 2>/dev/null || true
    svc wifi enable 2>/dev/null || true
    touched_services=0
  fi
  nh_finish_session "$RADIO"
  log "ABORT: $reason (Android restored)"
  exit 1
}

# Gate: fingerprint + patched module integrity, before touching anything
result=$(nh_check_fingerprint "$MODULE_PROP" "wifi" "$KO_PATH")
if [ "$result" != "OK" ]; then
  echo "ABORT: $result" >&2
  exit 1
fi

nh_begin_session "$RADIO" || { echo "ABORT: cannot begin session" >&2; exit 1; }
log "Acquiring Wi-Fi"

# Snapshot pre-state
nh_snapshot_put "$RADIO" wifi_enabled "$(dumpsys wifi 2>/dev/null | grep -c 'Wi-Fi is operational' || true)"
nh_snapshot_put "$RADIO" stock_module_sha256 "$(sha256sum "$STOCK_KO" | cut -d' ' -f1)"
nh_snapshot_put "$RADIO" hal_state "$(getprop init.svc.vendor.wifi_hal_legacy 2>/dev/null || echo unknown)"
nh_snapshot_put "$RADIO" con_mode "$(cat /sys/module/qca_cld3_kiwi_v2/parameters/con_mode 2>/dev/null || echo 0)"

# Quiesce Android Wi-Fi
svc wifi disable 2>/dev/null || true
sleep 2
stop vendor.wifi_hal_legacy 2>/dev/null || true
touched_services=1
sleep 2

# Unload stock module and load the patched one from the module dir.
# /vendor_dlkm is never written.
rmmod qca_cld3_kiwi_v2 2>/dev/null || true
stock_unloaded=1
insmod "$KO_PATH" || rollback "insmod patched module failed"
patched_loaded=1

# Create monitor interface
iw phy phy0 interface add mon0 type monitor 2>/dev/null || rollback "iw monitor interface failed"

# Smoke test
iw dev mon0 info >/dev/null 2>&1 || rollback "mon0 smoke test failed"

nh_mark_takeover "$RADIO"
log "TAKEOVER active"
echo "Wi-Fi takeover active. mon0 ready."
