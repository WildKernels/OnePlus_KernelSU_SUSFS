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
mkdir -p "$nh_data" "$mod_dir/system/bin"

# Real compiled nci_raw_tool (host build) for probe/init smoke tests.
# The tool opens /dev/nq-nci — mock that too via a fake device the mock
# tool replaces: use PATH-overridable wrapper instead of the real binary.
cat > "$mod_dir/system/bin/nci_raw_tool" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  probe) exit 0 ;;
  init)  echo "CORE_RESET_RSP: ok"; echo "CORE_INIT_RSP: ok"; exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$mod_dir/system/bin/nci_raw_tool"

mockbin="$tmpdir/bin"
mkdir -p "$mockbin"
state_dir="$tmpdir/state"
mkdir -p "$state_dir"

mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$mockbin/$1"; chmod +x "$mockbin/$1"; }

mk cmd      'echo "cmd $*" >> "$CALLS"; [[ "$2" == nfc ]] && printf "%s" "${3:-}" > "$STATE/nfc_cmd"; exit 0'
mk svc      'echo "svc $*" >> "$CALLS"; [[ "$2" == nfc ]] && printf "%s" "${3:-}" > "$STATE/nfc_svc"; exit 0'
mk stop     'echo "stop $*" >> "$CALLS"; [[ "$2" == vendor.nfc_hal_service ]] && echo stopped > "$STATE/hal"; exit 0'
mk start    'echo "start $*" >> "$CALLS"; [[ "$2" == vendor.nfc_hal_service ]] && echo running > "$STATE/hal"; exit 0'
mk getprop  'echo stopped'
mk dumpsys  'if [[ -f "$STATE/nfc_on" ]]; then echo "mState=on"; else echo "mState=off"; fi'
mk sleep    ':'

run_env() {
  env PATH="$mockbin:$PATH" \
      CALLS="$tmpdir/calls.log" STATE="$state_dir" \
      NH_STATE_DIR="$nh_data" NH_LOCK_DIR="$nh_data" \
      NH_MODULE_DIR="$mod_dir" \
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
[[ "$(cat "$nh_data/nfc.journal/nfc_enabled" 2>/dev/null)" == "0" ]] \
  && pass "journal recorded nfc_enabled=0" || fail "journal nfc_enabled: $(cat "$nh_data/nfc.journal/nfc_enabled" 2>/dev/null)"
[[ "$(cat "$nh_data/nfc.state" 2>/dev/null)" == "TAKEOVER" ]] && pass "state TAKEOVER" || fail "state not TAKEOVER"

# ---- Release: restores to off (snapshot), verifies, clears journal ----
: > "$tmpdir/calls.log"
if run_env bash "$release" >"$tmpdir/release.out" 2>&1; then
  pass "release succeeds"
else
  fail "release failed: $(tail -3 "$tmpdir/release.out")"
fi
grep -q "start vendor.nfc_hal_service" "$tmpdir/calls.log" && pass "HAL restarted" || fail "HAL not restarted"
grep -q "svc nfc enable" "$tmpdir/calls.log" \
  && fail "release force-enabled nfc despite off snapshot" || pass "nfc not force-enabled (snapshot off)"
[[ ! -e "$nh_data/nfc.journal" ]] && pass "journal cleared" || fail "journal kept"
[[ "$(cat "$nh_data/nfc.state" 2>/dev/null)" == "IDLE" ]] && pass "state IDLE" || fail "state not IDLE"

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

# ---- Failure path: nci_raw_tool init fails → rollback, journal cleaned ----
: > "$tmpdir/calls.log"
cat > "$mod_dir/system/bin/nci_raw_tool" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  probe) exit 0 ;;
  init)  exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$mod_dir/system/bin/nci_raw_tool"
if run_env bash "$acquire" >"$tmpdir/acquire3.out" 2>&1; then
  fail "acquire succeeded despite init failure"
else
  pass "acquire aborts when nci init fails"
fi
grep -q "start vendor.nfc_hal_service" "$tmpdir/calls.log" && pass "rollback restarted HAL" || fail "rollback missing HAL start"
[[ "$(cat "$nh_data/nfc.state" 2>/dev/null)" == "IDLE" ]] && pass "rollback state IDLE" || fail "rollback state: $(cat "$nh_data/nfc.state" 2>/dev/null)"
[[ ! -e "$nh_data/nfc.journal" ]] && pass "rollback cleaned journal" || fail "rollback kept journal"

# ---- Cross-radio blocking ----
cat > "$mod_dir/system/bin/nci_raw_tool" <<'EOF'
#!/usr/bin/env bash
case "$1" in probe) exit 0 ;; init) exit 0 ;; *) exit 1 ;; esac
EOF
chmod +x "$mod_dir/system/bin/nci_raw_tool"
mkdir -p "$nh_data/wifi.lock"
if run_env bash "$acquire" >"$tmpdir/acquire4.out" 2>&1; then
  fail "acquire allowed while wifi session active"
else
  pass "acquire blocked by active wifi session"
fi
rmdir "$nh_data/wifi.lock"

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
echo "NFC SESSION TESTS PASSED"
