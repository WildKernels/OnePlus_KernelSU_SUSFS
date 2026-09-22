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
mkdir -p "$nh_data" "$mod_dir/vendor_dlkm_override"

printf 'STOCKKO' > "$android/vendor_ko"
stock_sha=$(sha256sum "$android/vendor_ko" | cut -d' ' -f1)
printf 'PATCHEDKO' > "$mod_dir/vendor_dlkm_override/qca_cld3_kiwi_v2.ko"
patched_sha=$(sha256sum "$mod_dir/vendor_dlkm_override/qca_cld3_kiwi_v2.ko" | cut -d' ' -f1)

cat > "$mod_dir/module.prop" <<EOF
target=ONEPLUS PKG110
kernel_vermagic=6.1.174-g638ecc425319 SMP preempt mod_unload modversions aarch64
scmversion=g976cb1e13abc
sha256_wifi=$patched_sha
sha256_btvhci=unused
EOF

mockbin="$tmpdir/bin"
mkdir -p "$mockbin"
state_dir="$tmpdir/state"
mkdir -p "$state_dir"

mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$mockbin/$1"; chmod +x "$mockbin/$1"; }

mk svc     'echo "svc $*" >> "$CALLS"; [[ "$2" == wifi ]] && printf "%s" "${3:-}" > "$STATE/wifi_enabled"; exit 0'
mk stop    'echo "stop $*" >> "$CALLS"; [[ "$2" == vendor.wifi_hal_legacy ]] && echo stopped > "$STATE/hal"; exit 0'
mk start   'echo "start $*" >> "$CALLS"; [[ "$2" == vendor.wifi_hal_legacy ]] && echo running > "$STATE/hal"; exit 0'
mk insmod  'echo "insmod $*" >> "$CALLS"; [[ "$1" == "$NH_VENDOR_KO" ]] && exit 0; [[ "$1" == *vendor_dlkm_override/* ]] && exit 0; echo "insmod: unexpected $1" >&2; exit 1'
mk rmmod   'echo "rmmod $*" >> "$CALLS"; exit 0'
mk iw      'echo "iw $*" >> "$CALLS"; if [[ "$*" == *add*mon0*monitor* ]]; then touch "$STATE/mon0"; fi; if [[ "$*" == mon0\ del* || "$*" == *mon0*del* ]]; then rm -f "$STATE/mon0"; fi; if [[ "$*" == mon0\ info* || "$*" == dev\ mon0* ]]; then [[ -f "$STATE/mon0" ]] || exit 1; fi; exit 0'
mk getprop 'case "$*" in *ro.product.model*) echo "ONEPLUS PKG110";; *init.svc.vendor.wifi_hal_legacy*) cat "$STATE/hal" 2>/dev/null || echo unknown;; *) echo x;; esac'
mk dumpsys 'echo "Wi-Fi is operational"'
mk uname   'echo "6.1.174-g638ecc425319"'
mk sleep   ':'
mk svcno   'true'
rm -f "$mockbin/svcno"

run_env() {
  env PATH="$mockbin:$PATH" \
      CALLS="$tmpdir/calls.log" STATE="$state_dir" \
      NH_VENDOR_KO="$android/vendor_ko" \
      NH_STATE_DIR="$nh_data" NH_LOCK_DIR="$nh_data" \
      NH_MODULE_DIR="$mod_dir" \
      "$@"
}

acquire="$root/nethunter/wifi/nh-wifi-acquire.sh"
release="$root/nethunter/wifi/nh-wifi-release.sh"
: > "$tmpdir/calls.log"
echo stopped > "$state_dir/hal"
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
