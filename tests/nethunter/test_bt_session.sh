#!/usr/bin/env bash
set -euo pipefail

# Runs nh-bt-acquire.sh / nh-bt-release.sh against mocked Android commands.
# Verifies: fingerprint gate, journal snapshots, hci_vhci module loaded from
# /data/adb, bluebinder lifecycle, restore verification, and rollback.

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
mkdir -p "$nh_data" "$mod_dir/vendor_dlkm_override" "$mod_dir/system/bin" "$mod_dir/system/lib64" "$mod_dir/framework"
cp "$root"/nethunter/framework/*.sh "$mod_dir/framework/"
touch "$mod_dir/system/lib64/libgbinder.so" "$mod_dir/system/lib64/libglib-2.0.so"

printf 'VHCIKO' > "$mod_dir/vendor_dlkm_override/hci_vhci.ko"
ko_sha=$(sha256sum "$mod_dir/vendor_dlkm_override/hci_vhci.ko" | cut -d' ' -f1)

cat > "$mod_dir/module.prop" <<EOF
target=OP-ACE-5
device=pineapple
model=ONEPLUS PKG110
build_fingerprint=oneplus/PKG110/PKG110:16/TEST/release-keys
kernel_release=6.1.174-g638ecc425319
sha256_wifi=unused
sha256_btvhci=$ko_sha
EOF

# bluebinder mock: a real background process that keeps running
cat > "$mod_dir/system/bin/bluebinder" <<'EOF'
#!/usr/bin/env bash
[[ "${BLUEBINDER_EXIT:-0}" == 1 ]] && exit 1
echo $$ > "$BLUEBINDER_PID_FILE"
printf '%s\n' "$LD_LIBRARY_PATH" > "$BLUEBINDER_PID_FILE.ldpath"
trap 'exit 0' TERM
while :; do sleep 0.1; done
EOF
chmod +x "$mod_dir/system/bin/bluebinder"

mockbin="$tmpdir/bin"
mkdir -p "$mockbin"
state_dir="$tmpdir/state"
mkdir -p "$state_dir"

mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$mockbin/$1"; chmod +x "$mockbin/$1"; }

mk svc       'echo "svc $*" >> "$CALLS"; if [[ "$2" == bluetooth ]]; then printf "%s" "${3:-}" > "$STATE/bt_svc"; [[ "$3" == enable ]] && touch "$STATE/bt_on" || rm -f "$STATE/bt_on"; fi; exit 0'
mk rfkill    'echo "rfkill $*" >> "$CALLS"; if [[ "$1" == list ]]; then case "$(cat "$STATE/rfkill" 2>/dev/null)" in blocked) echo "Soft blocked: yes";; unblocked) echo "Soft blocked: no";; esac; elif [[ "$1" == block ]]; then echo blocked > "$STATE/rfkill"; elif [[ "$1" == unblock ]]; then echo unblocked > "$STATE/rfkill"; fi; exit 0'
mk insmod    'echo "insmod $*" >> "$CALLS"; [[ "$1" == *vendor_dlkm_override/* ]] && { [[ "${MOCK_NO_VHCI:-0}" == 1 ]] || touch "$NH_VHCI_NODE"; printf "hci_vhci 1 0 - Live 0x0\n" >> "$NH_MODULES_FILE"; exit 0; }; echo "insmod: unexpected $1" >&2; exit 1'
mk rmmod     'echo "rmmod $*" >> "$CALLS"; [[ "${MOCK_RMMOD_FAIL:-0}" == 1 ]] && exit 1; rm -f "$STATE/hci0" "$NH_VHCI_NODE"; grep -v "^hci_vhci " "$NH_MODULES_FILE" > "$NH_MODULES_FILE.tmp" || true; mv "$NH_MODULES_FILE.tmp" "$NH_MODULES_FILE"; exit 0'
mk hciconfig 'echo "hciconfig $*" >> "$CALLS"; if [[ "$*" == hci0\ up* ]]; then echo up > "$STATE/hci_up"; exit 0; fi; if [[ "$*" == hci0\ down* ]]; then rm -f "$STATE/hci_up"; exit 0; fi; if [[ -f "$STATE/hci0" ]]; then exit 0; else exit 1; fi'
mk getprop   'case "$*" in *ro.product.model*) echo "ONEPLUS PKG110";; *ro.product.device*) echo pineapple;; *ro.build.fingerprint*) echo oneplus/PKG110/PKG110:16/TEST/release-keys;; *init.svc.bluetooth*) cat "$STATE/hal" 2>/dev/null || echo unknown;; *) echo stopped;; esac'
mk dumpsys   'if [[ -f "$STATE/bt_on" ]]; then echo "state: ON"; else echo "state: OFF"; fi'
mk uname     'echo "6.1.174-g638ecc425319"'
mk sleep     ':'

run_env() {
  env PATH="$mockbin:$PATH" \
      CALLS="$tmpdir/calls.log" STATE="$state_dir" \
      BLUEBINDER_PID_FILE="$state_dir/bb.pid" \
      NH_MODULES_FILE="$state_dir/proc_modules" \
      NH_STATE_DIR="$nh_data" NH_LOCK_DIR="$nh_data" \
      NH_PACKAGE_ROOT="$mod_dir" NH_VHCI_NODE="$state_dir/vhci" \
      "$@"
}

export NH_STATE_DIR="$nh_data" NH_LOCK_DIR="$nh_data" NH_PACKAGE_ROOT="$mod_dir"
source "$root/nethunter/framework/nh-state.sh"
source "$root/nethunter/framework/nh-runtime.sh"

acquire="$root/nethunter/bt/nh-bt-acquire.sh"
release="$root/nethunter/bt/nh-bt-release.sh"
: > "$tmpdir/calls.log"
rm -f "$state_dir/hci0"
echo unblocked > "$state_dir/rfkill"
echo stopped > "$state_dir/hal"
: > "$state_dir/proc_modules"

# ---- Happy path ----
# hci0 appears: bluebinder mock writes hci0 marker via pid file watcher is
# overkill — simulate by touching hci0 right after bluebinder starts.
( while [ ! -f "$state_dir/bb.pid" ]; do sleep 0.05; done; touch "$state_dir/hci0"; ) &
watcher=$!

if run_env bash "$acquire" >"$tmpdir/acquire.out" 2>&1; then
  pass "acquire succeeds"
else
  fail "acquire failed: $(tail -3 "$tmpdir/acquire.out")"
fi
kill "$watcher" 2>/dev/null || true

grep -q "insmod $mod_dir/vendor_dlkm_override/hci_vhci.ko" "$tmpdir/calls.log" \
  && pass "hci_vhci loaded from /data/adb" || fail "hci_vhci not loaded from /data/adb"
[[ "$(cat "$nh_data/bt.journal/bt_enabled" 2>/dev/null)" == "0" ]] \
  && pass "journal recorded bt_enabled=0" || fail "journal bt_enabled: $(cat "$nh_data/bt.journal/bt_enabled" 2>/dev/null)"
[[ "$(cat "$nh_data/bt.state" 2>/dev/null)" == "TAKEOVER" ]] && pass "state TAKEOVER" || fail "state not TAKEOVER"
kill "$(cat "$state_dir/bb.pid")" 2>/dev/null || true
grep -q "$mod_dir/system/lib64" "$state_dir/bb.pid.ldpath" \
  && pass "bluebinder receives package runtime library path" || fail "bluebinder runtime library path missing"

# ---- Release happy path (BT was off before, restore must not force it on) ----
: > "$tmpdir/calls.log"
if run_env bash "$release" >"$tmpdir/release.out" 2>&1; then
  pass "release succeeds"
else
  fail "release failed: $(tail -3 "$tmpdir/release.out")"
fi
grep -q "rmmod hci_vhci" "$tmpdir/calls.log" && pass "hci_vhci unloaded" || fail "hci_vhci not unloaded"
grep -q "rfkill unblock" "$tmpdir/calls.log" && pass "rfkill unblocked" || fail "rfkill not unblocked"
[[ ! -e "$nh_data/bt.journal" ]] && pass "journal cleared" || fail "journal kept"
[[ "$(cat "$nh_data/bt.state" 2>/dev/null)" == "IDLE" ]] && pass "state IDLE" || fail "state not IDLE"

# ---- Dead bluebinder PID is harmless during release ----
: > "$tmpdir/calls.log"
rm -f "$state_dir/bt_on" "$state_dir/hci0"
echo unblocked > "$state_dir/rfkill"
( while [ ! -f "$state_dir/bb.pid" ]; do sleep 0.05; done; touch "$state_dir/hci0"; ) &
watcher=$!
if run_env bash "$acquire" >"$tmpdir/acquire-dead-pid.out" 2>&1; then pass "acquire for dead-PID release test"; else fail "dead-PID setup failed: $(tail -3 "$tmpdir/acquire-dead-pid.out")"; fi
kill "$watcher" 2>/dev/null || true
kill "$(cat "$state_dir/bb.pid")" 2>/dev/null || true
echo 999999 > "$nh_data/bluebinder.pid"
: > "$tmpdir/calls.log"
if run_env bash "$release" >"$tmpdir/release-dead-pid.out" 2>&1; then
  pass "release handles dead bluebinder PID"
else
  fail "release dead PID failed: $(tail -3 "$tmpdir/release-dead-pid.out")"
fi
[[ ! -e "$nh_data/bluebinder.pid" ]] && pass "dead bluebinder PID file removed" || fail "dead PID file retained"

# ---- Bluetooth initially enabled is enabled again on release ----
: > "$tmpdir/calls.log"
touch "$state_dir/bt_on"
rm -f "$state_dir/hci0"
( while [ ! -f "$state_dir/bb.pid" ]; do sleep 0.05; done; touch "$state_dir/hci0"; ) &
watcher=$!
if run_env bash "$acquire" >"$tmpdir/acquire-on.out" 2>&1; then pass "acquire succeeds with Bluetooth enabled"; else fail "acquire-on failed: $(tail -3 "$tmpdir/acquire-on.out")"; fi
kill "$watcher" 2>/dev/null || true
[[ "$(cat "$nh_data/bt.journal/bt_enabled" 2>/dev/null)" == 1 ]] && pass "journal recorded Bluetooth enabled" || fail "enabled snapshot wrong"
kill "$(cat "$state_dir/bb.pid")" 2>/dev/null || true
: > "$tmpdir/calls.log"
if run_env bash "$release" >"$tmpdir/release-on.out" 2>&1; then pass "release restores enabled Bluetooth"; else fail "release-on failed: $(tail -3 "$tmpdir/release-on.out")"; fi
grep -q 'svc bluetooth enable' "$tmpdir/calls.log" && pass "Bluetooth enable restored" || fail "release did not enable Bluetooth"
[[ -f "$state_dir/bt_on" ]] && pass "Bluetooth remains enabled" || fail "Bluetooth ended disabled"

# ---- VHCI device node missing causes rollback before bluebinder ----
: > "$tmpdir/calls.log"
rm -f "$state_dir/bt_on" "$state_dir/hci0" "$state_dir/vhci" "$state_dir/bb.pid"
echo unblocked > "$state_dir/rfkill"
if MOCK_NO_VHCI=1 run_env bash "$acquire" >"$tmpdir/acquire-no-vhci.out" 2>&1; then
  fail "acquire succeeded without /dev/vhci"
else
  pass "acquire aborts when /dev/vhci is missing"
fi
grep -q 'rmmod hci_vhci' "$tmpdir/calls.log" && pass "missing-node rollback unloaded hci_vhci" || fail "missing-node rollback left module"
[[ ! -e "$nh_data/bluebinder.pid" ]] && pass "missing-node rollback did not start bluebinder" || fail "bluebinder started without vhci node"
[[ "$(cat "$nh_data/bt.state" 2>/dev/null)" == IDLE ]] && pass "missing-node rollback restored IDLE" || fail "missing-node rollback state not IDLE"

# ---- bluebinder exit during wait triggers early rollback ----
: > "$tmpdir/calls.log"
rm -f "$state_dir/hci0" "$state_dir/vhci" "$state_dir/bb.pid"
if BLUEBINDER_EXIT=1 run_env bash "$acquire" >"$tmpdir/acquire-bb-exit.out" 2>&1; then
  fail "acquire succeeded after bluebinder exited"
else
  pass "acquire aborts when bluebinder exits"
fi
grep -q 'ROLLBACK: bluebinder exited before hci0 appeared' "$nh_data/bt.log" \
  && pass "bluebinder exit detected during bounded wait" || fail "bluebinder exit was not detected"
[[ "$(cat "$nh_data/bt.state" 2>/dev/null)" == IDLE ]] && pass "bluebinder exit rollback restored IDLE" || fail "bluebinder exit rollback state not IDLE"

# ---- Failed module unload keeps RECOVERY_REQUIRED until retry succeeds ----
: > "$tmpdir/calls.log"
rm -f "$state_dir/hci0" "$state_dir/vhci"
echo unblocked > "$state_dir/rfkill"
( while [ ! -f "$state_dir/bb.pid" ]; do sleep 0.05; done; touch "$state_dir/hci0"; ) &
watcher=$!
if run_env bash "$acquire" >"$tmpdir/acquire-rmmod.out" 2>&1; then pass "acquire for unload-failure test"; else fail "unload-failure setup failed"; fi
kill "$watcher" 2>/dev/null || true
kill "$(cat "$state_dir/bb.pid")" 2>/dev/null || true
if MOCK_RMMOD_FAIL=1 run_env bash "$release" >"$tmpdir/release-rmmod-fail.out" 2>&1; then
  fail "release succeeded when VHCI unload failed"
else
  pass "release reports VHCI unload failure"
fi
[[ "$(cat "$nh_data/bt.state" 2>/dev/null)" == RECOVERY_REQUIRED ]] && pass "unload failure retained RECOVERY_REQUIRED" || fail "unload failure state not RECOVERY_REQUIRED"
[[ -e "$nh_data/bt.journal/error" ]] && pass "unload failure retained reason" || fail "unload failure reason missing"
if run_env env NH_RECOVERY_MODE=1 bash "$release" >"$tmpdir/release-rmmod-retry.out" 2>&1; then
  pass "recovery release succeeds after unload retry"
else
  fail "recovery unload retry failed: $(tail -3 "$tmpdir/release-rmmod-retry.out")"
fi
[[ "$(cat "$nh_data/bt.state" 2>/dev/null)" == IDLE ]] && pass "successful unload retry clears recovery state" || fail "recovery state stayed active"

# ---- Unknown HAL/rfkill state blocks before Android changes ----
: > "$tmpdir/calls.log"
echo unknown > "$state_dir/hal"
echo unknown > "$state_dir/rfkill"
if run_env bash "$acquire" >"$tmpdir/acquire-unknown.out" 2>&1; then
  fail "acquire accepted unknown Bluetooth pre-state"
else
  pass "acquire rejects unknown Bluetooth pre-state"
fi
if grep -q 'svc bluetooth disable' "$tmpdir/calls.log"; then
  fail "Bluetooth service changed with unknown pre-state"
else
  pass "unknown-state rejection made no Bluetooth changes"
fi
[[ "$(cat "$nh_data/bt.state" 2>/dev/null)" == "IDLE" ]] && pass "unknown-state rejection cleaned session" || fail "unknown-state left session active"
echo stopped > "$state_dir/hal"
echo unblocked > "$state_dir/rfkill"

# ---- Failure path: hci0 never appears → rollback, no RECOVERY_REQUIRED ----
: > "$tmpdir/calls.log"
rm -f "$state_dir/hci0" "$state_dir/bb.pid"
if run_env bash "$acquire" >"$tmpdir/acquire2.out" 2>&1; then
  fail "acquire succeeded despite missing hci0"
else
  pass "acquire aborts when hci0 never appears"
fi
grep -q "rmmod hci_vhci" "$tmpdir/calls.log" && pass "rollback unloaded hci_vhci" || fail "rollback missing rmmod"
[[ "$(cat "$nh_data/bt.state" 2>/dev/null)" == "IDLE" ]] && pass "rollback state IDLE" || fail "rollback state: $(cat "$nh_data/bt.state" 2>/dev/null)"
[[ ! -e "$nh_data/bt.journal" ]] && pass "rollback cleaned journal" || fail "rollback kept journal"
[[ ! -e "$nh_data/bluebinder.pid" ]] && pass "rollback killed bluebinder" || fail "bluebinder pid file kept"

# ---- Mutual exclusion: wifi session blocks bt acquire ----
mkdir -p "$nh_data/wifi.lock"
if run_env bash "$acquire" >"$tmpdir/acquire3.out" 2>&1; then
  fail "acquire allowed while wifi session active"
else
  pass "acquire blocked by active wifi session"
fi
[[ "$(cat "$nh_data/bt.state" 2>/dev/null)" == "IDLE" ]] && pass "no bt lock left behind" || fail "bt state: $(cat "$nh_data/bt.state" 2>/dev/null)"
rmdir "$nh_data/wifi.lock"

# ---- Stale PID cannot signal unrelated process ----
nh_begin_session bt
nh_snapshot_put bt bt_enabled 0
nh_snapshot_put bt hal_state stopped
nh_snapshot_put bt rfkill_state unblocked
nh_mark_takeover bt
printf '%s\n' "$$" > "$nh_data/bluebinder.pid"
if run_env bash "$release" >"$tmpdir/release-unrelated-pid.out" 2>&1; then
  fail "release accepted unrelated bluebinder PID"
else
  pass "release rejects unrelated bluebinder PID"
fi
kill -0 "$$" 2>/dev/null && pass "test process was not signaled" || fail "release signaled test process"
[[ "$(cat "$nh_data/bt.state" 2>/dev/null)" == RECOVERY_REQUIRED ]] && pass "unrelated PID left recovery journal" || fail "unrelated PID did not require recovery"
rm -f "$nh_data/bluebinder.pid"
nh_finish_session bt

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
echo "BT SESSION TESTS PASSED"
