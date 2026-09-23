#!/system/bin/sh
set -euo pipefail

MODDIR="${MODPATH:?MODPATH must be set by the module installer}"
STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"

read_prop() {
  grep -m1 "^$1=" "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2-
}

TARGET=$(read_prop target || true)
EXPECTED_DEVICE=$(read_prop device || true)
EXPECTED_MODEL=$(read_prop model || true)
EXPECTED_FINGERPRINT=$(read_prop build_fingerprint || true)
EXPECTED_KERNEL=$(read_prop kernel_release || true)

ui_print "NetHunter Hardware Control for ${TARGET:-unknown}"

[ -n "$TARGET" ] || abort "Installation aborted: target metadata missing"
[ -n "$EXPECTED_DEVICE" ] || abort "Installation aborted: device metadata missing"
[ -n "$EXPECTED_MODEL" ] || abort "Installation aborted: model metadata missing"
[ -n "$EXPECTED_FINGERPRINT" ] || abort "Installation aborted: fingerprint metadata missing"
[ -n "$EXPECTED_KERNEL" ] || abort "Installation aborted: kernel metadata missing"

ACTUAL_DEVICE=$(getprop ro.product.device)
ACTUAL_MODEL=$(getprop ro.product.model)
ACTUAL_FINGERPRINT=$(getprop ro.build.fingerprint)
ACTUAL_KERNEL=$(uname -r)

if [ "$ACTUAL_DEVICE" != "$EXPECTED_DEVICE" ]; then
  ui_print "ERROR: device mismatch. Expected $EXPECTED_DEVICE, got $ACTUAL_DEVICE"
  abort "Installation aborted: device mismatch"
fi
if [ "$ACTUAL_MODEL" != "$EXPECTED_MODEL" ]; then
  ui_print "ERROR: model mismatch. Expected $EXPECTED_MODEL, got $ACTUAL_MODEL"
  abort "Installation aborted: model mismatch"
fi
if [ "$ACTUAL_FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]; then
  ui_print "ERROR: build fingerprint mismatch"
  abort "Installation aborted: fingerprint mismatch"
fi
if [ "$ACTUAL_KERNEL" != "$EXPECTED_KERNEL" ]; then
  ui_print "ERROR: kernel release mismatch. Expected $EXPECTED_KERNEL, got $ACTUAL_KERNEL"
  abort "Installation aborted: kernel release mismatch"
fi

mkdir -p "$STATE_DIR"
chmod 755 "$STATE_DIR"
ui_print "Module installed. Use nh-*-acquire scripts to activate."
ui_print "NO auto-activation at boot. Reboot restores stock."
