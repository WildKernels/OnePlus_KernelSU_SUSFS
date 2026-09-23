#!/bin/bash
set -euo pipefail

source nethunter/framework/nh-state.sh
source nethunter/framework/nh-runtime.sh

TMPDIR=$(mktemp -d)
export NH_STATE_DIR="$TMPDIR"
export NH_LOCK_DIR="$TMPDIR"

# Test: initial state is IDLE
state=$(nh_get_state wifi)
[ "$state" = "IDLE" ] || { echo "FAIL: expected IDLE, got $state"; exit 1; }

# Test: set_state changes state
nh_set_state wifi TAKEOVER
state=$(nh_get_state wifi)
[ "$state" = "TAKEOVER" ] || { echo "FAIL: expected TAKEOVER, got $state"; exit 1; }

# Test: acquire_lock creates a persistent lock directory
nh_acquire_lock wifi || { echo "FAIL: acquire_lock failed"; exit 1; }
[ -d "$NH_LOCK_DIR/wifi.lock" ] || { echo "FAIL: lock directory not created"; exit 1; }

# Test: release_lock removes lock directory and resets state
nh_release_lock wifi
[ ! -e "$NH_LOCK_DIR/wifi.lock" ] || { echo "FAIL: lock directory not removed"; exit 1; }
state=$(nh_get_state wifi)
[ "$state" = "IDLE" ] || { echo "FAIL: expected IDLE after release, got $state"; exit 1; }

# Test: session journal persists snapshots until successful release
nh_begin_session wifi || { echo "FAIL: begin_session failed"; exit 1; }
[ "$(nh_get_state wifi)" = "PREPARE" ] || { echo "FAIL: expected PREPARE"; exit 1; }
nh_snapshot_put wifi wifi_enabled 1
[ "$(nh_snapshot_get wifi wifi_enabled)" = "1" ] || { echo "FAIL: snapshot not saved"; exit 1; }
nh_mark_takeover wifi
[ "$(nh_get_state wifi)" = "TAKEOVER" ] || { echo "FAIL: expected TAKEOVER"; exit 1; }
nh_mark_recovery_required wifi "stock module reload failed"
[ "$(nh_get_state wifi)" = "RECOVERY_REQUIRED" ] || { echo "FAIL: recovery state not retained"; exit 1; }
[[ "$(nh_recover_status wifi)" == RECOVERY_REQUIRED ]] || { echo "FAIL: recovery status missing"; exit 1; }
[ -f "$NH_STATE_DIR/wifi.journal/error" ] || { echo "FAIL: recovery reason missing"; exit 1; }
if nh_begin_session wifi >/dev/null 2>&1; then
  echo "FAIL: acquire started over a recovery journal"
  exit 1
fi
[ "$(nh_get_state wifi)" = "RECOVERY_REQUIRED" ] || { echo "FAIL: acquire overwrote recovery state"; exit 1; }
[ -f "$NH_STATE_DIR/wifi.journal/error" ] || { echo "FAIL: acquire removed recovery journal"; exit 1; }
nh_finish_session wifi

# Test: mutual exclusion — another radio's active session blocks begin_session
mkdir -p "$NH_LOCK_DIR/bt.lock"
if nh_begin_session wifi >/dev/null 2>&1; then
  echo "FAIL: begin_session allowed while bt session active"
  exit 1
fi
[ "$(nh_get_state wifi)" = "IDLE" ] || { echo "FAIL: wifi state polluted by blocked begin"; exit 1; }
rmdir "$NH_LOCK_DIR/bt.lock"
nh_begin_session wifi || { echo "FAIL: begin_session blocked after other radio released"; exit 1; }
nh_finish_session wifi
[ "$(nh_get_state wifi)" = "IDLE" ] || { echo "FAIL: expected IDLE after finish"; exit 1; }
[ ! -e "$NH_STATE_DIR/wifi.journal" ] || { echo "FAIL: journal not removed after finish"; exit 1; }
[ ! -e "$NH_LOCK_DIR/wifi.lock" ] || { echo "FAIL: lock not removed after finish"; exit 1; }

# Test: radio names cannot escape the state directory
outside="$TMPDIR/outside"
mkdir "$outside"
if nh_begin_session '../outside' >/dev/null 2>&1; then
  echo "FAIL: traversal radio name started a session"
  exit 1
fi
[ -d "$outside" ] || { echo "FAIL: traversal radio name modified outside directory"; exit 1; }

# Test: invalid snapshot keys cannot escape the session journal
nh_begin_session wifi || { echo "FAIL: begin_session for invalid key test failed"; exit 1; }
if nh_snapshot_put wifi '../outside' value >/dev/null 2>&1; then
  echo "FAIL: traversal snapshot key was accepted"
  exit 1
fi
[ ! -e "$outside/value" ] || { echo "FAIL: traversal snapshot key wrote outside journal"; exit 1; }
nh_finish_session wifi

# State values are closed to known lifecycle labels.
nh_set_state wifi BOOT_RECOVERED
[ "$(nh_get_state wifi)" = "BOOT_RECOVERED" ] || { echo "FAIL: BOOT_RECOVERED state was not stored"; exit 1; }
if nh_set_state wifi '../../outside' 2>/dev/null; then
  echo "FAIL: invalid state value was accepted"
  exit 1
fi

echo "STATE TESTS PASSED"

# --- Fingerprint tests ---

source nethunter/framework/nh-fingerprint.sh

TMP_PROP="$TMPDIR/module.prop"
cat > "$TMP_PROP" <<EOF
target=OP-ACE-5
device=pineapple
model=ONEPLUS PKG110
build_fingerprint=oneplus/PKG110/PKG110:16/TEST/release-keys
kernel_release=6.1.174-g638ecc425319
sha256_wifi=abc123
sha256_btvhci=def456
EOF

FAKE_KO="$TMPDIR/fake.ko"
echo -n "fakeko" > "$FAKE_KO"
FAKE_SHA=$(sha256sum "$FAKE_KO" | cut -d' ' -f1)

sed -i "s/^sha256_wifi=.*/sha256_wifi=$FAKE_SHA/" "$TMP_PROP"

nh_get_target_model() { echo "ONEPLUS PKG110"; }
nh_get_target_device() { echo "pineapple"; }
nh_get_build_fingerprint() { echo "oneplus/PKG110/PKG110:16/TEST/release-keys"; }
nh_get_running_kernel_release() { echo "6.1.174-g638ecc425319"; }

result=$(nh_check_fingerprint "$TMP_PROP" "wifi" "$FAKE_KO" || true)
[ "$result" = "OK" ] || { echo "FAIL: expected OK, got $result"; exit 1; }

# Test: mismatch model
nh_get_target_model() { echo "WRONG-MODEL"; }
result=$(nh_check_fingerprint "$TMP_PROP" "wifi" "$FAKE_KO" || true)
[ "$result" = "MISMATCH_MODEL" ] || { echo "FAIL: expected MISMATCH_MODEL, got $result"; exit 1; }

# Test: mismatch device codename
nh_get_target_model() { echo "ONEPLUS PKG110"; }
nh_get_target_device() { echo "wrong-device"; }
result=$(nh_check_fingerprint "$TMP_PROP" "wifi" "$FAKE_KO" || true)
[ "$result" = "MISMATCH_DEVICE" ] || { echo "FAIL: expected MISMATCH_DEVICE, got $result"; exit 1; }

# Test: mismatch build fingerprint
nh_get_target_device() { echo "pineapple"; }
nh_get_build_fingerprint() { echo "wrong/fingerprint"; }
result=$(nh_check_fingerprint "$TMP_PROP" "wifi" "$FAKE_KO" || true)
[ "$result" = "MISMATCH_BUILD_FINGERPRINT" ] || { echo "FAIL: expected MISMATCH_BUILD_FINGERPRINT, got $result"; exit 1; }

# Test: mismatch kernel release
nh_get_build_fingerprint() { echo "oneplus/PKG110/PKG110:16/TEST/release-keys"; }
nh_get_running_kernel_release() { echo "wrong-release"; }
result=$(nh_check_fingerprint "$TMP_PROP" "wifi" "$FAKE_KO" || true)
[ "$result" = "MISMATCH_KERNEL_RELEASE" ] || { echo "FAIL: expected MISMATCH_KERNEL_RELEASE, got $result"; exit 1; }

# Test: component hash mismatch
nh_get_running_kernel_release() { echo "6.1.174-g638ecc425319"; }
BAD_KO="$TMPDIR/bad.ko"
echo -n 'tampered' > "$BAD_KO"
result=$(nh_check_fingerprint "$TMP_PROP" wifi "$BAD_KO" || true)
[ "$result" = "MISMATCH_SHA256" ] || { echo "FAIL: expected MISMATCH_SHA256, got $result"; exit 1; }

rm -rf "$TMPDIR"
echo "FINGERPRINT TESTS PASSED"
