#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NH_PACKAGE_ROOT="${NH_PACKAGE_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"
source "$NH_PACKAGE_ROOT/framework/nh-state.sh"
source "$NH_PACKAGE_ROOT/framework/nh-runtime.sh"

RADIO=wifi
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
NH_LOCK_DIR="${NH_LOCK_DIR:-$NH_STATE_DIR}"
STOCK_KO="${NH_VENDOR_KO:-/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko}"
CON_MODE_PATH="${NH_WIFI_CON_MODE_PATH:-/sys/module/qca_cld3_kiwi_v2/parameters/con_mode}"

log() { nh_log "$RADIO" "$*"; }

state=$(nh_get_state "$RADIO")
if [ "$state" = IDLE ] || [ "$state" = BOOT_RECOVERED ]; then
  echo "Wi-Fi already in stock state."
  exit 0
fi
if [ "$state" != TAKEOVER ] && { [ "$state" != RECOVERY_REQUIRED ] || [ "${NH_RECOVERY_MODE:-0}" != 1 ]; }; then
  echo "Wi-Fi is in $state; use nh-recover (journal kept)." >&2
  exit 1
fi

log "Releasing Wi-Fi"
nh_set_state "$RADIO" RESTORE

iw dev mon0 del 2>/dev/null || true
rmmod qca_cld3_kiwi_v2 2>/dev/null || true
if ! insmod "$STOCK_KO" 2>/dev/null; then
  nh_mark_recovery_required "$RADIO" "stock module insmod failed on release"
  echo "ERROR: stock module reload failed; Android Wi-Fi needs recovery" >&2
  exit 1
fi
con_mode=$(nh_snapshot_get "$RADIO" con_mode 2>/dev/null || true)
if [ -z "$con_mode" ] || ! printf '%s\n' "$con_mode" > "$CON_MODE_PATH"; then
  nh_mark_recovery_required "$RADIO" "stock Wi-Fi con_mode restore failed"
  echo "ERROR: Wi-Fi con_mode restore failed; journal retained" >&2
  exit 1
fi

hal_state=$(nh_snapshot_get "$RADIO" hal_state 2>/dev/null || echo unknown)
wifi_enabled=$(nh_snapshot_get "$RADIO" wifi_enabled 2>/dev/null || echo 1)
case "$hal_state" in
  running) start vendor.wifi_hal_legacy 2>/dev/null || true ;;
  stopped) stop vendor.wifi_hal_legacy 2>/dev/null || true ;;
  *) nh_mark_recovery_required "$RADIO" "saved Wi-Fi HAL state is unknown"; exit 1 ;;
esac
if [ "$wifi_enabled" = 1 ]; then
  svc wifi enable 2>/dev/null || true
else
  svc wifi disable 2>/dev/null || true
fi

sleep 2
if ! nh_recover_verify "$RADIO" >/dev/null 2>&1; then
  log "RECOVERY_REQUIRED: stock Wi-Fi verification failed"
  nh_mark_recovery_required "$RADIO" "stock Wi-Fi verification failed on release"
  echo "ERROR: Wi-Fi restore could not be verified; journal retained" >&2
  exit 1
fi

nh_finish_session "$RADIO"
log "RESTORED to stock"
echo "Wi-Fi restored to stock."
