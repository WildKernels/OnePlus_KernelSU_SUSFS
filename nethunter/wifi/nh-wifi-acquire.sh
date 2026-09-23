#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NH_PACKAGE_ROOT="${NH_PACKAGE_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"
source "$NH_PACKAGE_ROOT/framework/nh-state.sh"
source "$NH_PACKAGE_ROOT/framework/nh-runtime.sh"
source "$NH_PACKAGE_ROOT/framework/nh-fingerprint.sh"

RADIO=wifi
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
NH_LOCK_DIR="${NH_LOCK_DIR:-$NH_STATE_DIR}"
STOCK_KO="${NH_VENDOR_KO:-/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko}"
KO_PATH="$NH_PACKAGE_ROOT/vendor_dlkm_override/qca_cld3_kiwi_v2.ko"
MODULE_PROP="$NH_PACKAGE_ROOT/module.prop"
CON_MODE_PATH="${NH_WIFI_CON_MODE_PATH:-/sys/module/qca_cld3_kiwi_v2/parameters/con_mode}"

log() { nh_log "$RADIO" "$*"; }

restore_android_wifi() {
  local hal_enabled wifi_enabled
  hal_enabled=$(nh_snapshot_get "$RADIO" hal_state 2>/dev/null || echo unknown)
  wifi_enabled=$(nh_snapshot_get "$RADIO" wifi_enabled 2>/dev/null || echo 1)
  case "$hal_enabled" in
    running) start vendor.wifi_hal_legacy 2>/dev/null || true ;;
    stopped) stop vendor.wifi_hal_legacy 2>/dev/null || true ;;
  esac
  if [ "$wifi_enabled" = 1 ]; then
    svc wifi enable 2>/dev/null || true
  else
    svc wifi disable 2>/dev/null || true
  fi
}

restore_wifi_con_mode() {
  local value
  value=$(nh_snapshot_get "$RADIO" con_mode) || return 1
  printf '%s\n' "$value" > "$CON_MODE_PATH"
}

touched_services=0
stock_unloaded=0
patched_loaded=0

rollback() {
  local reason="$1"
  log "ROLLBACK: $reason"
  if [ "$patched_loaded" = 1 ]; then
    rmmod qca_cld3_kiwi_v2 2>/dev/null || true
    patched_loaded=0
  fi
  if [ "$stock_unloaded" = 1 ]; then
    if insmod "$STOCK_KO" 2>/dev/null; then restore_wifi_con_mode || true; fi
    stock_unloaded=0
  fi
  if [ "$touched_services" = 1 ]; then
    restore_android_wifi
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

# Fingerprint and artifact checks run before session state or Android changes.
if result=$(nh_check_fingerprint "$MODULE_PROP" wifi "$KO_PATH"); then
  :
else
  echo "ABORT: $result" >&2
  exit 1
fi
stock_sha=$(sha256sum "$STOCK_KO" 2>/dev/null | cut -d' ' -f1) || {
  echo "ABORT: stock Wi-Fi module is unavailable" >&2
  exit 1
}
[ -n "$stock_sha" ] || { echo "ABORT: stock Wi-Fi module hash is empty" >&2; exit 1; }

nh_begin_session "$RADIO" || { echo "ABORT: cannot begin session" >&2; exit 1; }
log "Acquiring Wi-Fi"

# Persist every restore input before quiescing Android.
if nh_is_enabled wifi; then wifi_enabled=1; else wifi_enabled=0; fi
hal_state=$(getprop init.svc.vendor.wifi_hal_legacy 2>/dev/null || true)
con_mode=$(cat "$CON_MODE_PATH" 2>/dev/null || true)
nh_snapshot_put "$RADIO" wifi_enabled "$wifi_enabled"
nh_snapshot_put "$RADIO" stock_module_sha256 "$stock_sha"
nh_snapshot_put "$RADIO" hal_state "$hal_state"
nh_snapshot_put "$RADIO" con_mode "$con_mode"
if [ -z "$con_mode" ]; then
  nh_finish_session "$RADIO"
  echo "ABORT: Wi-Fi con_mode cannot be snapshotted" >&2
  exit 1
fi
case "$hal_state" in
  running|stopped) ;;
  *) nh_finish_session "$RADIO"; echo "ABORT: Wi-Fi HAL state is unknown" >&2; exit 1 ;;
esac

svc wifi disable 2>/dev/null || true
sleep 2
stop vendor.wifi_hal_legacy 2>/dev/null || true
touched_services=1
sleep 2

# Load the patched module from the package. The vendor partition stays read-only.
rmmod qca_cld3_kiwi_v2 2>/dev/null || true
stock_unloaded=1
insmod "$KO_PATH" || rollback "insmod patched module failed"
patched_loaded=1

iw phy phy0 interface add mon0 type monitor 2>/dev/null || rollback "iw monitor interface failed"
iw dev mon0 info >/dev/null 2>&1 || rollback "mon0 smoke test failed"

nh_mark_takeover "$RADIO"
log "TAKEOVER active"
echo "Wi-Fi takeover active. mon0 ready."
