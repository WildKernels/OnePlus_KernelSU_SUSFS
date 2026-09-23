#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

export NH_STATE_DIR="$tmpdir/state"
export NH_LOCK_DIR="$NH_STATE_DIR"
export NH_FRAMEWORK_DIR="$root/nethunter/framework"
export NH_PACKAGE_ROOT="$tmpdir/package"
mkdir -p "$NH_STATE_DIR"

source "$root/nethunter/framework/nh-state.sh"
source "$root/nethunter/framework/nh-runtime.sh"

nh_begin_session wifi
nh_mark_takeover wifi
nh_mark_recovery_required wifi 'module unload failed'
if nh_begin_session bt >/dev/null 2>&1; then
  echo 'FAIL: started bt over wifi recovery journal' >&2
  exit 1
fi
[[ "$(nh_recover_status wifi)" == RECOVERY_REQUIRED ]]
recover_cli="$root/nethunter/framework/nh-recover.sh"
[[ -x "$recover_cli" ]] || { echo 'FAIL: recovery CLI is missing' >&2; exit 1; }
status=$(NH_STATE_DIR="$NH_STATE_DIR" NH_LOCK_DIR="$NH_LOCK_DIR" \
  NH_PACKAGE_ROOT="$root/nethunter" bash "$recover_cli" status wifi)
[[ "$status" == RECOVERY_REQUIRED ]]

nh_verify_stock_wifi() { [[ "${STOCK_WIFI_OK:-0}" == 1 ]]; }
STOCK_WIFI_OK=1 nh_recover_boot wifi
[[ "$(nh_get_state wifi)" == BOOT_RECOVERED ]]
[[ ! -e "$NH_STATE_DIR/wifi.journal" ]]
[[ ! -e "$NH_LOCK_DIR/wifi.lock" ]]

nh_begin_session wifi
nh_mark_takeover wifi
nh_mark_recovery_required wifi 'patched module still loaded'
if STOCK_WIFI_OK=0 nh_recover_boot wifi; then
  echo 'FAIL: boot recovery cleared journal while takeover remained' >&2
  exit 1
fi
[[ "$(nh_get_state wifi)" == RECOVERY_REQUIRED ]]
[[ -f "$NH_STATE_DIR/wifi.journal/error" ]]

# A stale lock without a journal has no trustworthy snapshot; keep it blocked.
mkdir -p "$NH_LOCK_DIR/bt.lock"
nh_set_state bt TAKEOVER
if nh_recover_boot bt; then
  echo 'FAIL: boot recovery trusted stale lock without journal' >&2
  exit 1
fi
[[ "$(nh_get_state bt)" == RECOVERY_REQUIRED ]]
[[ -f "$NH_STATE_DIR/bt.journal/error" ]]
rm -rf "$NH_STATE_DIR/bt.journal"
rmdir "$NH_LOCK_DIR/bt.lock"
nh_set_state bt IDLE

# Recovery invokes only the selected package release entrypoint and confirms
# that the script cleared its own journal and lock.
mkdir -p "$NH_PACKAGE_ROOT/wifi"
cat > "$NH_PACKAGE_ROOT/wifi/nh-wifi-release.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "$NH_FRAMEWORK_DIR/nh-state.sh"
exit 1
SH
chmod +x "$NH_PACKAGE_ROOT/wifi/nh-wifi-release.sh"
if nh_recover_restore wifi; then
  echo 'FAIL: recovery accepted a failed release script' >&2
  exit 1
fi
[[ -d "$NH_STATE_DIR/wifi.journal" ]]
[[ "$(nh_get_state wifi)" == RECOVERY_REQUIRED ]]

cat > "$NH_PACKAGE_ROOT/wifi/nh-wifi-release.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${NH_RECOVERY_MODE:-0}" == 1 ]]
source "$NH_FRAMEWORK_DIR/nh-state.sh"
source "$NH_FRAMEWORK_DIR/nh-runtime.sh"
nh_verify_stock_wifi() { return 0; }
nh_recover_verify wifi >/dev/null
nh_finish_session wifi
SH
chmod +x "$NH_PACKAGE_ROOT/wifi/nh-wifi-release.sh"
nh_recover_restore wifi
[[ "$(nh_get_state wifi)" == IDLE ]]
[[ ! -e "$NH_STATE_DIR/wifi.journal" ]]

nh_begin_session nfc
nh_mark_recovery_required nfc 'test restore'
nh_recover_restore nfc 2>/dev/null && {
  echo 'FAIL: recovery executed missing NFC release script' >&2
  exit 1
}

# Boot hook must preserve an explicit package root and must not erase an
# unjournaled lock/state pair into IDLE.
boot_state="$tmpdir/boot-state"
mkdir -p "$boot_state/wifi.lock"
printf 'TAKEOVER\n' > "$boot_state/wifi.state"
NH_STATE_DIR="$boot_state"
NH_LOCK_DIR="$boot_state"
NH_PACKAGE_ROOT="$root/nethunter"
source "$root/nethunter/module/post-fs-data.sh"
[[ "$(nh_get_state wifi)" == RECOVERY_REQUIRED ]] || { echo 'FAIL: boot hook did not retain RECOVERY_REQUIRED' >&2; exit 1; }
[[ -f "$boot_state/wifi.journal/error" ]] || { echo 'FAIL: boot hook did not retain recovery reason' >&2; exit 1; }
[[ -d "$boot_state/wifi.lock" ]] || { echo 'FAIL: boot hook deleted stale lock' >&2; exit 1; }

echo 'Recovery contract tests passed'
