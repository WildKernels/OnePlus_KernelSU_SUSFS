#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NH_PACKAGE_ROOT="${NH_PACKAGE_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"
source "$NH_PACKAGE_ROOT/framework/nh-state.sh"
source "$NH_PACKAGE_ROOT/framework/nh-runtime.sh"

RADIO=nfc
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
NH_LOCK_DIR="${NH_LOCK_DIR:-$NH_STATE_DIR}"

log() { nh_log "$RADIO" "$*"; }

state=$(nh_get_state "$RADIO")
if [ "$state" = IDLE ] || [ "$state" = BOOT_RECOVERED ]; then
  echo "NFC already in stock state."
  exit 0
fi
if [ "$state" != TAKEOVER ] && { [ "$state" != RECOVERY_REQUIRED ] || [ "${NH_RECOVERY_MODE:-0}" != 1 ]; }; then
  echo "NFC is in $state; use nh-recover (journal kept)." >&2
  exit 1
fi

log "Releasing NFC"
nh_set_state "$RADIO" RESTORE

nfc_enabled=$(nh_snapshot_get "$RADIO" nfc_enabled 2>/dev/null || echo 1)
hal_state=$(nh_snapshot_get "$RADIO" hal_state 2>/dev/null || echo unknown)
case "$hal_state" in
  running) start vendor.nfc_hal_service 2>/dev/null || true ;;
  stopped) stop vendor.nfc_hal_service 2>/dev/null || true ;;
  *) nh_mark_recovery_required "$RADIO" "saved NFC HAL state is unknown"; exit 1 ;;
esac
if [ "$nfc_enabled" = 1 ]; then
  svc nfc enable 2>/dev/null || true
  cmd nfc enable-nfc 2>/dev/null || true
else
  svc nfc disable 2>/dev/null || true
  cmd nfc disable-nfc persist 2>/dev/null || true
fi

sleep 2
if ! nh_recover_verify "$RADIO" >/dev/null 2>&1; then
  log "RECOVERY_REQUIRED: stock NFC verification failed"
  nh_mark_recovery_required "$RADIO" "stock NFC verification failed on release"
  echo "ERROR: NFC restore could not be verified; journal retained" >&2
  exit 1
fi

nh_finish_session "$RADIO"
log "RESTORED to stock"
echo "NFC restored to stock."
