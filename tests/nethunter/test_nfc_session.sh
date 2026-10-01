#!/usr/bin/env bash
set -euo pipefail

# Runs nh-nfc-acquire.sh / nh-nfc-release.sh against mocked Android commands.
# Verifies: probe gate, journal snapshots, HAL/service teardown, restore
# verification against the snapshot, rollback, and cross-radio blocking.

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0
pass() { pass=$((pass + 1)); echo "  PASS: $1"; }
fail() { fail=$((fail + 1)); echo "  FAIL: $1"; }

android="$tmpdir"
nh_data="$android/data/adb/nethunter"
mod_dir="$android/data/adb/modules/nethunter_takeover"
mkdir -p "$nh_data" "$mod_dir/system/bin" "$mod_dir/vendor_dlkm_override" "$mod_dir/framework"
cp "$root"/nethunter/framework/*.sh "$mod_dir/framework/"

# Mock session server for Android lifecycle tests; C protocol tests use PTY.
cat > "$mod_dir/system/bin/nci_raw_tool" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  probe) exit 0 ;;
  session)
    socket_path="$3"
    : > "$socket_path"
    trap 'rm -f "$socket_path"; exit 0' TERM
    while :; do read -t 1 _ || true; done
    ;;
  init)  [[ -e "$3" ]] || exit 1; echo "CORE_RESET_RSP: ok"; echo "CORE_INIT_RSP: ok"; exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$mod_dir/system/bin/nci_raw_tool"
tool_sha=$(sha256sum "$mod_dir/system/bin/nci_raw_tool" | cut -d' ' -f1)
printf 'STOCK_NFC_KO' > "$android/vendor_nfc.ko"
stock_nfc_sha=$(sha256sum "$android/vendor_nfc.ko" | cut -d' ' -f1)
printf 'PATCHED_NFC_KO' > "$mod_dir/vendor_dlkm_override/nxp-nci.ko"
patched_nfc_sha=$(sha256sum "$mod_dir/vendor_dlkm_override/nxp-nci.ko" | cut -d' ' -f1)
cat > "$mod_dir/module.prop" <<EOF
target=OP-ACE-5
device=pineapple
model=ONEPLUS PKG110
build_fingerprint=oneplus/PKG110/PKG110:16/TEST/release-keys
kernel_release=6.1.174-g638ecc425319
sha256_nci_raw_tool=$tool_sha
sha256_nxp_nci=$patched_nfc_sha
EOF

mockbin="$tmpdir/bin"
mkdir -p "$mockbin"
state_dir="$tmpdir/state"
mkdir -p "$state_dir"
echo running > "$state_dir/hal"
printf 'nxp_nci 1 0 - Live 0x0\n' > "$state_dir/proc_modules"

update_tool_hash() {
  local hash
  hash=$(sha256sum "$mod_dir/system/bin/nci_raw_tool" | cut -d' ' -f1)
  sed -i "s/^sha256_nci_raw_tool=.*/sha256_nci_raw_tool=$hash/" "$mod_dir/module.prop"
}

mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$mockbin/$1"; chmod +x "$mockbin/$1"; }

mk cmd      'echo "cmd $*" >> "$CALLS"; if [[ "$2" == nfc ]]; then printf "%s" "${3:-}" > "$STATE/nfc_cmd"; [[ "$3" == enable-nfc ]] && touch "$STATE/nfc_on" || [[ "$3" == disable-nfc ]] && rm -f "$STATE/nfc_on"; fi; exit 0'
mk svc      'echo "svc $*" >> "$CALLS"; if [[ "$2" == nfc ]]; then printf "%s" "${3:-}" > "$STATE/nfc_svc"; [[ "$3" == enable ]] && touch "$STATE/nfc_on" || [[ "$3" == disable ]] && rm -f "$STATE/nfc_on"; fi; exit 0'
mk stop     'echo "stop $*" >> "$CALLS"; [[ "$1" == vendor.nfc_hal_service ]] && echo stopped > "$STATE/hal"; exit 0'
mk start    'echo "start $*" >> "$CALLS"; [[ "$1" == vendor.nfc_hal_service ]] && echo running > "$STATE/hal"; exit 0'
mk insmod   'echo "insmod $*" >> "$CALLS"; if [[ "$1" == "$NH_NFC_VENDOR_KO" || "$1" == *vendor_dlkm_override/nxp-nci.ko ]]; then printf "nxp_nci 1 0 - Live 0x0\\n" > "$NH_MODULES_FILE"; exit 0; fi; exit 1'
mk rmmod    'echo "rmmod $*" >> "$CALLS"; [[ "$1" == nxp_nci ]] || exit 1; : > "$NH_MODULES_FILE"; exit 0'
mk rmmod    'echo "rmmod $*" >> "$CALLS"; [[ "$1" == nxp_nci ]] || exit 1; : > "$NH_MODULES_FILE"; exit 0'
mk getprop  'case "$*" in *ro.product.model*) echo "ONEPLUS PKG110";; *ro.product.device*) echo pineapple;; *ro.build.fingerprint*) echo oneplus/PKG110/PKG110:16/TEST/release-keys;; *init.svc.vendor.nfc_hal_service*) cat "$STATE/hal" 2>/dev/null || echo unknown;; *) echo stopped;; esac'
mk dumpsys  'if [[ -f "$STATE/nfc_on" ]]; then echo "mState=on"; else echo "mState=off"; fi'
mk uname    'echo "6.1.174-g638ecc425319"'
mk sleep    ':'

run_env() {
  env PATH="$mockbin:$PATH" \
      CALLS="$tmpdir/calls.log" STATE="$state_dir" \
      NH_STATE_DIR="$nh_data" NH_LOCK_DIR="$nh_data" \
      NH_MODULES_FILE="$state_dir/proc_modules" NH_NFC_VENDOR_KO="$android/vendor_nfc.ko" \
      NH_PACKAGE_ROOT="$mod_dir" NH_KERNEL_RELEASE="6.1.174-g638ecc425319" \
      "$@"
}

acquire="$root/nethunter/nfc/nh-nfc-acquire.sh"
release="$root/nethunter/nfc/nh-nfc-release.sh"
: > "$tmpdir/calls.log"

# ---- Happy path: NFC was off before takeover ----
if run_env bash "$acquire" >"$tmpdir/acquire.out" 2>&1; then
  pass "acquire succeeds"
else
  fail "acquire failed: $(tail -3 "$tmpdir/acquire.out")"
fi

grep -q "stop vendor.nfc_hal_service" "$tmpdir/calls.log" && pass "HAL stopped" || fail "HAL not stopped"
grep -q "insmod $mod_dir/vendor_dlkm_override/nxp-nci.ko" "$tmpdir/calls.log" && pass "patched NXP driver loaded" || fail "patched NXP driver not loaded"
[[ "$(cat "$nh_data/nfc.journal/nfc_enabled" 2>/dev/null)" == "0" ]] \
  && pass "journal recorded nfc_enabled=0" || fail "journal nfc_enabled: $(cat "$nh_data/nfc.journal/nfc_enabled" 2>/dev/null)"
[[ "$(cat "$nh_data/nfc.journal/stock_module_sha256" 2>/dev/null)" == "$stock_nfc_sha" ]] \
  && pass "journal recorded stock NFC hash" || fail "journal missing stock NFC hash"
[[ "$(cat "$nh_data/nfc.state" 2>/dev/null)" == "TAKEOVER" ]] && pass "state TAKEOVER" || fail "state not TAKEOVER"
[[ -f "$nh_data/nci_raw_tool.pid" ]] && pass "journaled NFC session process" || fail "NFC session PID missing"

# ---- Release: restores to off (snapshot), verifies, clears journal ----
: > "$tmpdir/calls.log"
if run_env bash "$release" >"$tmpdir/release.out" 2>&1; then
  pass "release succeeds"
else
  fail "release failed: $(tail -3 "$tmpdir/release.out")"
fi
grep -q "start vendor.nfc_hal_service" "$tmpdir/calls.log" && pass "HAL restarted" || fail "HAL not restarted"
grep -q "insmod $android/vendor_nfc.ko" "$tmpdir/calls.log" && pass "stock NXP driver reloaded" || fail "stock NXP driver not reloaded"
grep -q "svc nfc enable" "$tmpdir/calls.log" \
  && fail "release force-enabled nfc despite off snapshot" || pass "nfc not force-enabled (snapshot off)"
[[ ! -e "$nh_data/nfc.journal" ]] && pass "journal cleared" || fail "journal kept"
[[ "$(cat "$nh_data/nfc.state" 2>/dev/null)" == "IDLE" ]] && pass "state IDLE" || fail "state not IDLE"
[[ ! -e "$nh_data/nci_raw_tool.pid" ]] && pass "NFC session process stopped" || fail "NFC session PID remained"

# ---- Happy path 2: NFC was on before takeover, release re-enables + verifies ----
: > "$tmpdir/calls.log"
touch "$state_dir/nfc_on"
if run_env bash "$acquire" >"$tmpdir/acquire2.out" 2>&1; then
  pass "acquire succeeds (nfc on snapshot)"
else
  fail "acquire2 failed: $(tail -3 "$tmpdir/acquire2.out")"
fi
[[ "$(cat "$nh_data/nfc.journal/nfc_enabled" 2>/dev/null)" == "1" ]] \
  && pass "journal recorded nfc_enabled=1" || fail "journal nfc_enabled wrong"

: > "$tmpdir/calls.log"
if run_env bash "$release" >"$tmpdir/release2.out" 2>&1; then
  pass "release succeeds (nfc on snapshot)"
else
  fail "release2 failed: $(tail -3 "$tmpdir/release2.out")"
fi
grep -q "svc nfc enable" "$tmpdir/calls.log" && pass "nfc re-enabled per snapshot" || fail "nfc not re-enabled"
[[ "$(cat "$nh_data/nfc.state" 2>/dev/null)" == "IDLE" ]] && pass "state IDLE after on-restore" || fail "state not IDLE"

# ---- Unknown HAL state blocks before Android changes ----
: > "$tmpdir/calls.log"
echo unknown > "$state_dir/hal"
if run_env bash "$acquire" >"$tmpdir/acquire-unknown.out" 2>&1; then
  fail "acquire accepted unknown NFC HAL state"
else
  pass "acquire rejects unknown NFC HAL state"
fi
if grep -q -E 'cmd nfc|svc nfc|stop vendor.nfc_hal_service' "$tmpdir/calls.log"; then
  fail "NFC services changed with unknown pre-state"
else
  pass "unknown-state rejection made no NFC changes"
fi
[[ "$(cat "$nh_data/nfc.state" 2>/dev/null)" == "IDLE" ]] && pass "unknown-state rejection cleaned session" || fail "unknown-state left session active"
echo running > "$state_dir/hal"
printf 'nxp_nci 1 0 - Live 0x0\n' > "$state_dir/proc_modules"

# ---- Failure path: nci_raw_tool init fails → rollback, journal cleaned ----
: > "$tmpdir/calls.log"
cat > "$mod_dir/system/bin/nci_raw_tool" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  probe) exit 0 ;;
  session) socket_path="$3"; : > "$socket_path"; trap 'rm -f "$socket_path"; exit 0' TERM; while :; do read -t 1 _ || true; done ;;
  init)  exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$mod_dir/system/bin/nci_raw_tool"
update_tool_hash
if run_env bash "$acquire" >"$tmpdir/acquire3.out" 2>&1; then
  fail "acquire succeeded despite init failure"
else
  pass "acquire aborts when nci init fails"
fi
grep -q "start vendor.nfc_hal_service" "$tmpdir/calls.log" && pass "rollback restarted HAL" || fail "rollback missing HAL start"
grep -q "rmmod nxp_nci" "$tmpdir/calls.log" && pass "rollback unloaded patched NXP driver" || fail "rollback missing patched driver unload"
grep -q "insmod $android/vendor_nfc.ko" "$tmpdir/calls.log" && pass "rollback reloaded stock NXP driver" || fail "rollback missing stock driver reload"
[[ "$(cat "$nh_data/nfc.state" 2>/dev/null)" == "IDLE" ]] && pass "rollback state IDLE" || fail "rollback state: $(cat "$nh_data/nfc.state" 2>/dev/null)"
[[ ! -e "$nh_data/nfc.journal" ]] && pass "rollback cleaned journal" || fail "rollback kept journal"

# ---- Cross-radio blocking ----
cat > "$mod_dir/system/bin/nci_raw_tool" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  probe) exit 0 ;;
  session) socket_path="$3"; : > "$socket_path"; trap 'rm -f "$socket_path"; exit 0' TERM; while :; do read -t 1 _ || true; done ;;
  init) [[ -e "$3" ]] && exit 0 || exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$mod_dir/system/bin/nci_raw_tool"
update_tool_hash
mkdir -p "$nh_data/wifi.lock"
if run_env bash "$acquire" >"$tmpdir/acquire4.out" 2>&1; then
  fail "acquire allowed while wifi session active"
else
  pass "acquire blocked by active wifi session"
fi
rmdir "$nh_data/wifi.lock"

# ---- Guard: abort before rmmod when the module still has open holders ----
# A live /dev/nq-nci open keeps nxp_nci refcount > 0 (field 3 of
# /proc/modules). The acquire must roll back without calling rmmod.
: > "$tmpdir/calls.log"
echo running > "$state_dir/hal"
printf 'nxp_nci 1 1 - Live 0x0\n' > "$state_dir/proc_modules"
if run_env bash "$acquire" >"$tmpdir/acquire-hold.out" 2>&1; then
  fail "acquire proceeded while nxp_nci had open holders"
else
  pass "acquire aborts while nxp_nci has open holders"
fi
if grep -q "rmmod nxp_nci" "$tmpdir/calls.log"; then
  fail "acquire called rmmod while nxp_nci had open holders"
else
  pass "acquire skipped rmmod while nxp_nci had open holders"
fi
[[ "$(cat "$nh_data/nfc.state" 2>/dev/null)" == "IDLE" ]] \
  && pass "holder abort restored IDLE" || fail "holder abort left state $(cat "$nh_data/nfc.state" 2>/dev/null)"

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
echo "NFC SESSION TESTS PASSED"
