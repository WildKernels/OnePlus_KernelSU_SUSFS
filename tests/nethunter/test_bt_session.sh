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
mkdir -p "$nh_data" "$mod_dir/vendor_dlkm_override" "$mod_dir/system/bin" "$mod_dir/framework"
cp "$root"/nethunter/framework/*.sh "$mod_dir/framework/"

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
echo $$ > "$BLUEBINDER_PID_FILE"
trap 'exit 0' TERM
while :; do sleep 0.1; done
EOF
chmod +x "$mod_dir/system/bin/bluebinder"

mockbin="$tmpdir/bin"
mkdir -p "$mockbin"
state_dir="$tmpdir/state"
mkdir -p "$state_dir"

mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$mockbin/$1"; chmod +x "$mockbin/$1"; }

mk svc       'echo "svc $*" >> "$CALLS"; [[ "$2" == bluetooth ]] && printf "%s" "${3:-}" > "$STATE/bt_svc"; exit 0'
mk rfkill    'echo "rfkill $*" >> "$CALLS"; if [[ "$1" == list ]]; then case "$(cat "$STATE/rfkill" 2>/dev/null)" in blocked) echo "Soft blocked: yes";; unblocked) echo "Soft blocked: no";; esac; elif [[ "$1" == block ]]; then echo blocked > "$STATE/rfkill"; elif [[ "$1" == unblock ]]; then echo unblocked > "$STATE/rfkill"; fi; exit 0'
mk insmod    'echo "insmod $*" >> "$CALLS"; [[ "$1" == *vendor_dlkm_override/* ]] && { touch "$NH_VHCI_NODE"; exit 0; }; echo "insmod: unexpected $1" >&2; exit 1'
mk rmmod     'echo "rmmod $*" >> "$CALLS"; rm -f "$STATE/hci0" "$NH_VHCI_NODE"; exit 0'
mk hciconfig 'echo "hciconfig $*" >> "$CALLS"; if [[ "$*" == hci0\ up* ]]; then echo up > "$STATE/hci_up"; exit 0; fi; if [[ "$*" == hci0\ down* ]]; then rm -f "$STATE/hci_up"; exit 0; fi; if [[ -f "$STATE/hci0" ]]; then exit 0; else exit 1; fi'
mk getprop   'case "$*" in *ro.product.model*) echo "ONEPLUS PKG110";; *ro.product.device*) echo pineapple;; *ro.build.fingerprint*) echo oneplus/PKG110/PKG110:16/TEST/release-keys;; *init.svc.bluetooth*) cat "$STATE/hal" 2>/dev/null || echo unknown;; *) echo stopped;; esac'
mk dumpsys   'if [[ -f "$STATE/bt_on" ]]; then echo "state: ON"; else echo "state: OFF"; fi'
mk uname     'echo "6.1.174-g638ecc425319"'
mk sleep     ':'

run_env() {
  env PATH="$mockbin:$PATH" \
      CALLS="$tmpdir/calls.log" STATE="$state_dir" \
      BLUEBINDER_PID_FILE="$state_dir/bb.pid" \
      NH_STATE_DIR="$nh_data" NH_LOCK_DIR="$nh_data" \
      NH_PACKAGE_ROOT="$mod_dir" NH_VHCI_NODE="$state_dir/vhci" \
      "$@"
}

acquire="$root/nethunter/bt/nh-bt-acquire.sh"
release="$root/nethunter/bt/nh-bt-release.sh"
: > "$tmpdir/calls.log"
rm -f "$state_dir/hci0"
echo unblocked > "$state_dir/rfkill"
echo stopped > "$state_dir/hal"

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

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
echo "BT SESSION TESTS PASSED"
