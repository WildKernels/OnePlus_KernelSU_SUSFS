#!/usr/bin/env bash
set -euo pipefail

# Runs nh-wifi-acquire.sh / nh-wifi-release.sh against mocked Android commands.
# Verifies: /vendor_dlkm never written, module loaded from /data/adb module dir,
# journal snapshots + cleanup, restore verification, rollback on failure.

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
mkdir -p "$nh_data" "$mod_dir/vendor_dlkm_override" "$mod_dir/framework"
cp "$root"/nethunter/framework/*.sh "$mod_dir/framework/"

printf 'STOCKKO' > "$android/vendor_ko"
stock_sha=$(sha256sum "$android/vendor_ko" | cut -d' ' -f1)
printf 'PATCHEDKO' > "$mod_dir/vendor_dlkm_override/qca_cld3_kiwi_v2.ko"
patched_sha=$(sha256sum "$mod_dir/vendor_dlkm_override/qca_cld3_kiwi_v2.ko" | cut -d' ' -f1)

cat > "$mod_dir/module.prop" <<EOF
target=OP-ACE-5
device=pineapple
model=ONEPLUS PKG110
build_fingerprint=oneplus/PKG110/PKG110:16/TEST/release-keys
kernel_release=6.1.174-g638ecc425319
sha256_wifi=$patched_sha
sha256_btvhci=unused
EOF

mockbin="$tmpdir/bin"
mkdir -p "$mockbin"
state_dir="$tmpdir/state"
mkdir -p "$state_dir"
echo 7 > "$state_dir/con_mode"

mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$mockbin/$1"; chmod +x "$mockbin/$1"; }

mk svc     'echo "svc $*" >> "$CALLS"; if [[ "$2" == wifi ]]; then printf "%s" "${3:-}" > "$STATE/wifi_enabled"; [[ "$3" == enable ]] && touch "$STATE/wifi_on" || rm -f "$STATE/wifi_on"; fi; exit 0'
mk stop    'echo "stop $*" >> "$CALLS"; [[ "$2" == vendor.wifi_hal_legacy ]] && echo stopped > "$STATE/hal"; exit 0'
mk start   'echo "start $*" >> "$CALLS"; [[ "$2" == vendor.wifi_hal_legacy ]] && echo running > "$STATE/hal"; exit 0'
mk insmod  'echo "insmod $*" >> "$CALLS"; if [[ "$1" == "$NH_VENDOR_KO" || "$1" == *vendor_dlkm_override/* ]]; then echo 0 > "$STATE/con_mode"; exit 0; fi; echo "insmod: unexpected $1" >&2; exit 1'
mk rmmod   'echo "rmmod $*" >> "$CALLS"; exit 0'
mk iw      'echo "iw $*" >> "$CALLS"; if [[ "$*" == *add*mon0*monitor* ]]; then touch "$STATE/mon0"; fi; if [[ "$*" == mon0\ del* || "$*" == *mon0*del* ]]; then rm -f "$STATE/mon0"; fi; if [[ "$*" == mon0\ info* || "$*" == dev\ mon0* ]]; then [[ -f "$STATE/mon0" ]] || exit 1; fi; exit 0'
mk getprop 'case "$*" in *ro.product.model*) echo "ONEPLUS PKG110";; *ro.product.device*) echo pineapple;; *ro.build.fingerprint*) echo oneplus/PKG110/PKG110:16/TEST/release-keys;; *init.svc.vendor.wifi_hal_legacy*) cat "$STATE/hal" 2>/dev/null || echo unknown;; *) echo x;; esac'
mk dumpsys '[[ -f "$STATE/wifi_on" ]] && echo "Wi-Fi is operational" || echo "Wi-Fi is disabled"'
mk uname   'echo "6.1.174-g638ecc425319"'
mk sleep   ':'
mk svcno   'true'
rm -f "$mockbin/svcno"

run_env() {
  env PATH="$mockbin:$PATH" \
      CALLS="$tmpdir/calls.log" STATE="$state_dir" \
      NH_VENDOR_KO="$android/vendor_ko" \
      NH_WIFI_CON_MODE_PATH="$state_dir/con_mode" \
      NH_STATE_DIR="$nh_data" NH_LOCK_DIR="$nh_data" \
      NH_PACKAGE_ROOT="$mod_dir" \
      "$@"
}

acquire="$root/nethunter/wifi/nh-wifi-acquire.sh"
release="$root/nethunter/wifi/nh-wifi-release.sh"
: > "$tmpdir/calls.log"
echo stopped > "$state_dir/hal"
touch "$state_dir/wifi_on"
rm -f "$state_dir/mon0"

# ---- Happy path ----
if run_env bash "$acquire" >"$tmpdir/acquire.out" 2>&1; then
  pass "acquire succeeds"
else
  fail "acquire failed: $(tail -3 "$tmpdir/acquire.out")"
fi

grep -q "insmod $mod_dir/vendor_dlkm_override/qca_cld3_kiwi_v2.ko" "$tmpdir/calls.log" \
  && pass "patched module loaded from /data/adb" || fail "patched module not loaded from /data/adb"
grep -q "cp " "$tmpdir/calls.log" \
  && fail "acquire used cp (must not touch vendor_dlkm)" || pass "no cp into vendor_dlkm"
[[ -f "$state_dir/mon0" ]] && pass "mon0 created" || fail "mon0 missing"
[[ "$(cat "$nh_data/wifi.journal/stock_module_sha256" 2>/dev/null)" == "$stock_sha" ]] \
  && pass "journal recorded stock sha" || fail "journal missing stock sha"
[[ "$(cat "$nh_data/wifi.state" 2>/dev/null)" == "TAKEOVER" ]] && pass "state TAKEOVER" || fail "state not TAKEOVER"

: > "$tmpdir/calls.log"
if run_env bash "$release" >"$tmpdir/release.out" 2>&1; then
  pass "release succeeds"
else
  fail "release failed: $(tail -3 "$tmpdir/release.out")"
fi

grep -q "insmod $android/vendor_ko" "$tmpdir/calls.log" \
  && pass "stock module reloaded from vendor path" || fail "stock module not reloaded"
[[ ! -e "$nh_data/wifi.journal" ]] && pass "journal cleared" || fail "journal kept after success"
[[ "$(cat "$nh_data/wifi.state" 2>/dev/null)" == "IDLE" ]] && pass "state IDLE" || fail "state not IDLE"
[[ "$(cat "$state_dir/con_mode")" == 7 ]] && pass "con_mode restored from snapshot" || fail "con_mode not restored"

# ---- Disabled Wi-Fi stays disabled after release ----
: > "$tmpdir/calls.log"
rm -f "$state_dir/wifi_on"
if run_env bash "$acquire" >"$tmpdir/acquire-off.out" 2>&1; then
  pass "acquire succeeds with Wi-Fi initially disabled"
else
  fail "acquire-off failed: $(tail -3 "$tmpdir/acquire-off.out")"
fi
[[ "$(cat "$nh_data/wifi.journal/wifi_enabled" 2>/dev/null)" == 0 ]] && pass "journal recorded Wi-Fi disabled" || fail "disabled Wi-Fi snapshot wrong"
: > "$tmpdir/calls.log"
if run_env bash "$release" >"$tmpdir/release-off.out" 2>&1; then
  pass "release restores disabled Wi-Fi state"
else
  fail "release-off failed: $(tail -3 "$tmpdir/release-off.out")"
fi
grep -q 'svc wifi enable' "$tmpdir/calls.log" && fail "release enabled Wi-Fi against snapshot" || pass "release did not enable Wi-Fi"
[[ ! -e "$state_dir/wifi_on" ]] && pass "Wi-Fi remains disabled" || fail "Wi-Fi became enabled"

# ---- Unknown HAL state blocks before Android changes ----
: > "$tmpdir/calls.log"
echo unknown > "$state_dir/hal"
if run_env bash "$acquire" >"$tmpdir/acquire-unknown.out" 2>&1; then
  fail "acquire accepted unknown Wi-Fi HAL state"
else
  pass "acquire rejects unknown Wi-Fi HAL state"
fi
if grep -q 'svc wifi disable' "$tmpdir/calls.log"; then
  fail "Wi-Fi service changed with unknown pre-state"
else
  pass "unknown HAL rejection made no Wi-Fi changes"
fi
[[ "$(cat "$nh_data/wifi.state" 2>/dev/null)" == "IDLE" ]] && pass "unknown HAL rejection cleaned session" || fail "unknown HAL left state active"
echo stopped > "$state_dir/hal"

# ---- Failure path: patched insmod fails → rollback, no RECOVERY_REQUIRED ----
: > "$tmpdir/calls.log"
rm -rf "$nh_data/wifi.journal" "$nh_data/wifi.lock"
cat > "$mockbin/insmod" <<'EOF'
#!/usr/bin/env bash
echo "insmod $*" >> "$CALLS"
[[ "$1" == "$NH_VENDOR_KO" ]] && exit 0
exit 1
EOF
chmod +x "$mockbin/insmod"
if run_env bash "$acquire" >"$tmpdir/acquire2.out" 2>&1; then
  fail "acquire succeeded despite insmod failure"
else
  pass "acquire aborts when patched insmod fails"
fi
[[ "$(cat "$nh_data/wifi.state" 2>/dev/null)" == "IDLE" ]] && pass "rollback restored state to IDLE" || fail "rollback state: $(cat "$nh_data/wifi.state" 2>/dev/null)"
[[ ! -e "$nh_data/wifi.journal" ]] && pass "rollback cleaned journal" || fail "rollback kept journal"

# ---- Release failure path: stock insmod fails → RECOVERY_REQUIRED ----
: > "$tmpdir/calls.log"
cat > "$mockbin/insmod" <<'EOF'
#!/usr/bin/env bash
echo "insmod $*" >> "$CALLS"
[[ "$1" == "$NH_VENDOR_KO" ]] && exit 1
exit 0
EOF
chmod +x "$mockbin/insmod"
touch "$state_dir/mon0"
if run_env bash "$acquire" >"$tmpdir/acquire3.out" 2>&1; then
  : > "$tmpdir/calls.log"
  if run_env bash "$release" >"$tmpdir/release2.out" 2>&1; then
    fail "release succeeded despite stock insmod failure"
  else
    pass "release fails when stock reload fails"
  fi
  [[ "$(cat "$nh_data/wifi.state" 2>/dev/null)" == "RECOVERY_REQUIRED" ]] \
    && pass "state RECOVERY_REQUIRED retained" || fail "state not RECOVERY_REQUIRED: $(cat "$nh_data/wifi.state" 2>/dev/null)"
  [[ -e "$nh_data/wifi.journal/error" ]] && pass "recovery reason in journal" || fail "no recovery reason"
  # acquire must refuse while recovery pending
  if run_env bash "$acquire" >"$tmpdir/acquire4.out" 2>&1; then
    fail "acquire allowed over RECOVERY_REQUIRED"
  else
    pass "acquire blocked by pending recovery journal"
  fi
else
  fail "setup: acquire for recovery test failed: $(tail -3 "$tmpdir/acquire3.out")"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
echo "WIFI SESSION TESTS PASSED"
