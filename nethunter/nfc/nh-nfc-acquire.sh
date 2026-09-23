#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NH_PACKAGE_ROOT="${NH_PACKAGE_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"
source "$NH_PACKAGE_ROOT/framework/nh-state.sh"
source "$NH_PACKAGE_ROOT/framework/nh-runtime.sh"
source "$NH_PACKAGE_ROOT/framework/nh-fingerprint.sh"

RADIO=nfc
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
NH_LOCK_DIR="${NH_LOCK_DIR:-$NH_STATE_DIR}"
NCI_TOOL="$NH_PACKAGE_ROOT/system/bin/nci_raw_tool"
MODULE_PROP="$NH_PACKAGE_ROOT/module.prop"

log() { nh_log "$RADIO" "$*"; }

restore_android_nfc() {
  local enabled hal_state
  enabled=$(nh_snapshot_get "$RADIO" nfc_enabled 2>/dev/null || echo 1)
  hal_state=$(nh_snapshot_get "$RADIO" hal_state 2>/dev/null || echo unknown)
  case "$hal_state" in
    running) start vendor.nfc_hal_service 2>/dev/null || true ;;
    stopped) stop vendor.nfc_hal_service 2>/dev/null || true ;;
  esac
  if [ "$enabled" = 1 ]; then
    svc nfc enable 2>/dev/null || true
    cmd nfc enable-nfc 2>/dev/null || true
  else
    svc nfc disable 2>/dev/null || true
    cmd nfc disable-nfc persist 2>/dev/null || true
  fi
}

touched_services=0

rollback() {
  local reason="$1"
  log "ROLLBACK: $reason"
  if [ "$touched_services" = 1 ]; then
    restore_android_nfc
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

[ -x "$NCI_TOOL" ] || { echo "ABORT: nci_raw_tool not found at $NCI_TOOL" >&2; exit 1; }
if result=$(nh_check_fingerprint "$MODULE_PROP" nci_raw_tool "$NCI_TOOL"); then
  :
else
  echo "ABORT: $result" >&2
  exit 1
fi

nh_begin_session "$RADIO" || { echo "ABORT: cannot begin session" >&2; exit 1; }
log "Acquiring NFC"

if nh_is_enabled nfc; then nfc_enabled=1; else nfc_enabled=0; fi
hal_state=$(getprop init.svc.vendor.nfc_hal_service 2>/dev/null || true)
nh_snapshot_put "$RADIO" nfc_enabled "$nfc_enabled"
nh_snapshot_put "$RADIO" hal_state "$hal_state"
case "$hal_state" in
  running|stopped) ;;
  *) nh_finish_session "$RADIO"; echo "ABORT: NFC HAL state is unknown" >&2; exit 1 ;;
esac

touched_services=1
cmd nfc disable-nfc persist 2>/dev/null || true
svc nfc disable 2>/dev/null || true
sleep 2
stop vendor.nfc_hal_service 2>/dev/null || true
sleep 2

"$NCI_TOOL" probe || rollback "nci_raw_tool probe failed after HAL quiesce"
"$NCI_TOOL" init || rollback "nci_raw_tool init failed"

nh_mark_takeover "$RADIO" || rollback "could not mark NFC takeover"
log "TAKEOVER active"
echo "NFC takeover active. /dev/nq-nci available to NetHunter."
