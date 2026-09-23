#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [ -z "${NH_PACKAGE_ROOT:-}" ]; then
  if [ -f "$SCRIPT_DIR/framework/nh-state.sh" ]; then
    NH_PACKAGE_ROOT="$SCRIPT_DIR"
  else
    NH_PACKAGE_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
  fi
fi
source "$NH_PACKAGE_ROOT/framework/nh-state.sh"
source "$NH_PACKAGE_ROOT/framework/nh-runtime.sh"

NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
NH_LOCK_DIR="${NH_LOCK_DIR:-$NH_STATE_DIR}"
mkdir -p "$NH_STATE_DIR"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$NH_STATE_DIR/boot.log"; }

log 'Boot check: verifying stock state; takeover stays disabled'
for radio in wifi bt nfc usb; do
  if nh_recover_boot "$radio"; then
    state=$(nh_get_state "$radio")
    if [ "$state" = BOOT_RECOVERED ]; then
      log "$radio: stock state verified after interrupted session"
    fi
  else
    log "$radio: RECOVERY_REQUIRED; journal retained"
  fi
done
