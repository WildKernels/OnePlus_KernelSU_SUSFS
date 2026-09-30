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
NFC_KO="$NH_PACKAGE_ROOT/vendor_dlkm_override/nxp-nci.ko"
STOCK_NFC_KO="${NH_NFC_VENDOR_KO:-/vendor_dlkm/lib/modules/nxp-nci.ko}"
NFC_NODE="${NH_NFC_NODE:-/dev/nq-nci}"
NCI_SOCKET="$NH_STATE_DIR/nci.sock"
NCI_PID="$NH_STATE_DIR/nci_raw_tool.pid"
MODULE_PROP="$NH_PACKAGE_ROOT/module.prop"

log() { nh_log "$RADIO" "$*"; }

stop_nci_session() {
  local pid i
  [ -f "$NCI_PID" ] || { rm -f "$NCI_SOCKET"; return 0; }
  pid=$(cat "$NCI_PID")
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  if kill -0 "$pid" 2>/dev/null && ! nh_process_matches "$pid" nci_raw_tool; then
    return 1
  fi
  kill "$pid" 2>/dev/null || true
  i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 5 ]; do
    sleep 1
    i=$((i + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
    sleep 1
  fi
  if kill -0 "$pid" 2>/dev/null; then return 1; fi
  rm -f "$NCI_PID" "$NCI_SOCKET"
}

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
stock_unloaded=0
patched_loaded=0

rollback() {
  local reason="$1"
  log "ROLLBACK: $reason"
  if [ "$NCI_PID" != "" ] && [ -f "$NCI_PID" ]; then
    stop_nci_session || true
  fi
  if [ "$patched_loaded" = 1 ]; then
    rmmod nxp_nci 2>/dev/null || true
    patched_loaded=0
  fi
  if [ "$stock_unloaded" = 1 ]; then
    insmod "$STOCK_NFC_KO" 2>/dev/null || true
    stock_unloaded=0
  fi
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
if result=$(nh_check_fingerprint "$MODULE_PROP" nxp_nci "$NFC_KO"); then
  :
else
  echo "ABORT: $result" >&2
  exit 1
fi
stock_sha=$(sha256sum "$STOCK_NFC_KO" 2>/dev/null | cut -d' ' -f1) || {
  echo "ABORT: stock NXP NFC module unavailable" >&2
  exit 1
}
[ -n "$stock_sha" ] || { echo "ABORT: stock NXP NFC module hash is empty" >&2; exit 1; }
nh_module_loaded nxp_nci || { echo "ABORT: stock NXP NFC driver is not loaded" >&2; exit 1; }
if [ -f "$NCI_PID" ]; then
  old_pid=$(cat "$NCI_PID")
  case "$old_pid" in
    ''|*[!0-9]*) echo "ABORT: invalid stale NFC session PID" >&2; exit 1 ;;
  esac
  if kill -0 "$old_pid" 2>/dev/null; then
    if nh_process_matches "$old_pid" nci_raw_tool; then
      echo "ABORT: NFC session process already active" >&2
      exit 1
    fi
    echo "ABORT: stale NFC PID now belongs to another process" >&2
    exit 1
  fi
  rm -f "$NCI_PID" "$NCI_SOCKET"
fi

nh_begin_session "$RADIO" || { echo "ABORT: cannot begin session" >&2; exit 1; }
log "Acquiring NFC"

if nh_is_enabled nfc; then nfc_enabled=1; else nfc_enabled=0; fi
hal_state=$(getprop init.svc.vendor.nfc_hal_service 2>/dev/null || true)
nh_snapshot_put "$RADIO" nfc_enabled "$nfc_enabled"
nh_snapshot_put "$RADIO" hal_state "$hal_state"
nh_snapshot_put "$RADIO" stock_module_sha256 "$stock_sha"
case "$hal_state" in
  running|stopped) ;;
  *) nh_finish_session "$RADIO"; echo "ABORT: NFC HAL state is unknown" >&2; exit 1 ;;
esac

touched_services=1
cmd nfc disable-nfc persist 2>/dev/null || true
svc nfc disable 2>/dev/null || true
stop vendor.nfc_hal_service 2>/dev/null || true
if ! nh_wait_service_stopped init.svc.vendor.nfc_hal_service \
     init.svc_debug_pid.vendor.nfc_hal_service 10; then
  rollback "NFC HAL did not stop"
fi
# A dead HAL may still hold /dev/nq-nci briefly; unloading under a live
# holder is what wedged the module lock in testing.
i=0
while [ "$i" -lt 5 ] && ! nh_node_is_free "$NFC_NODE"; do
  sleep 1
  i=$((i + 1))
done
if ! nh_node_is_free "$NFC_NODE"; then
  rollback "a process still holds $NFC_NODE"
fi

if ! rmmod nxp_nci 2>/dev/null; then
  rollback "stock nxp_nci unload failed"
fi
stock_unloaded=1
insmod "$NFC_KO" || rollback "patched nxp-nci module load failed"
patched_loaded=1

"$NCI_TOOL" session --socket "$NCI_SOCKET" </dev/null >/dev/null 2>&1 &
session_pid=$!
if ! printf '%s\n' "$session_pid" > "$NCI_PID"; then
  kill "$session_pid" 2>/dev/null || true
  rollback "cannot write NCI session PID file"
fi
chmod 600 "$NCI_PID"
i=0
while [ "$i" -lt 10 ] && [ ! -e "$NCI_SOCKET" ]; do
  pid=$(cat "$NCI_PID")
  kill -0 "$pid" 2>/dev/null || rollback "nci session exited before socket became ready"
  sleep 1
  i=$((i + 1))
done
[ -e "$NCI_SOCKET" ] || rollback "nci session socket did not appear"
"$NCI_TOOL" init --socket "$NCI_SOCKET" || rollback "nci_raw_tool init failed"

nh_mark_takeover "$RADIO" || rollback "could not mark NFC takeover"
log "TAKEOVER active"
echo "NFC takeover active. NCI session owns /dev/nq-nci."
