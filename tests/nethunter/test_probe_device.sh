#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
probe="$root/scripts/nethunter/probe_device.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fake_adb="$tmpdir/adb"
log="$tmpdir/adb.log"

cat > "$fake_adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$@" >> "$ADB_LOG"
printf '\n' >> "$ADB_LOG"

case "${1:-}" in
  get-state)
    printf '%s\n' "${ADB_STATE:-device}"
    ;;
  shell)
    case "${2:-}" in
      'getprop ro.product.model') printf '%s\n' 'ONEPLUS PKG110' ;;
      'getprop ro.product.device') printf '%s\n' 'pineapple' ;;
      'getprop ro.build.fingerprint') printf '%s\n' 'oneplus/PKG110/PKG110:16/TEST/release-keys' ;;
      'getprop ro.vendor.build.fingerprint') printf '%s\n' 'oneplus/PKG110/vendor:16/TEST/release-keys' ;;
      'getprop ro.build.version.incremental') printf '%s\n' 'TEST' ;;
      'getprop ro.boot.slot_suffix') printf '%s\n' '_a' ;;
      'getprop init.svc.vendor.nfc_hal_service') printf '%s\n' 'running' ;;
      'getprop init.svc.bluetooth') printf '%s\n' 'running' ;;
      'getprop init.svc.bluetooth 2>/dev/null || true') printf '%s\n' 'running' ;;
      'cat /proc/sys/kernel/osrelease 2>/dev/null || uname -r') printf '%s\n' '6.1.174-g638ecc425319' ;;
      'cat /proc/version') printf '%s\n' 'Linux version 6.1.174 test scmversion g976cb1e13abc' ;;
      'getenforce') printf '%s\n' 'Enforcing' ;;
      'uname -m') printf '%s\n' 'aarch64' ;;
      'test -d /data/local/nhsystem && echo present || echo absent') printf '%s\n' 'present' ;;
      'cat /proc/modules') printf '%s\n' 'qca_cld3_kiwi_v2 1 0 - Live 0x0' ;;
      'sha256sum /vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko') printf '%s\n' 'abc123  /vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko' ;;
      'command -v modinfo >/dev/null 2>&1 && modinfo /vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko || true') printf '%s\n' 'vermagic: 6.1.174-g638ecc425319 SMP preempt mod_unload modversions aarch64' ;;
      'cat /sys/module/qca_cld3_kiwi_v2/parameters/con_mode 2>/dev/null || true') printf '%s\n' '0' ;;
      'iw dev 2>/dev/null || true') printf '%s\n' 'Interface wlan0' ;;
      'iw phy 2>/dev/null || true') printf '%s\n' 'Wiphy phy0' ;;
      'rfkill list 2>/dev/null || true') printf '%s\n' '0: bluetooth: Bluetooth' ;;
      'dumpsys bluetooth_manager 2>/dev/null || true') printf '%s\n' 'enabled: true' ;;
      'service list 2>/dev/null | grep -i bluetooth || true') printf '%s\n' 'bluetooth_manager: [android.bluetooth.IBluetoothManager]' ;;
      'ls -l /dev/vhci 2>/dev/null || true') printf '%s\n' '' ;;
      'ls -l /dev/nq-nci 2>/dev/null || true') printf '%s\n' 'crw-rw---- nfc nfc /dev/nq-nci' ;;
      'modinfo /vendor_dlkm/lib/modules/nxp-nci.ko 2>/dev/null || true') printf '%s\n' 'name: nxp_nci' ;;
      'getprop init.svc.vendor.nfc_hal_service 2>/dev/null || true') printf '%s\n' 'running' ;;
      'dumpsys nfc 2>/dev/null || true') printf '%s\n' 'mState=on' ;;
      'getprop | grep -i nfc || true') printf '%s\n' '[ro.nfc.port]: [I2C]' ;;
      'getprop sys.usb.config') printf '%s\n' 'mtp,adb' ;;
      'for role in /sys/class/usb_role/*/role; do [ -r "$role" ] && printf "%s=%s\n" "$role" "$(cat "$role")"; done') printf '%s\n' '/sys/class/usb_role/a600000.dwc3/role=device' ;;
      'ls -1 /config/usb_gadget 2>/dev/null || true') printf '%s\n' 'g1' ;;
      'for udc in /sys/class/udc/*; do [ -e "$udc" ] && basename "$udc"; done') printf '%s\n' 'a600000.dwc3' ;;
      'ls -1 /config/usb_gadget/g1/functions 2>/dev/null || true') printf '%s\n' 'mtp.gs0' 'ffs.adb' ;;
      'service list 2>/dev/null | grep -i gnss || true') printf '%s\n' 'android.hardware.gnss.IGnss/default' ;;
      'dumpsys location 2>/dev/null || true') printf '%s\n' 'Location Manager State: enabled' ;;
      *) printf '%s\n' "unexpected shell command: ${2:-}" >&2; exit 1 ;;
    esac
    ;;
  *)
    printf '%s\n' "unexpected adb command: ${1:-}" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fake_adb"

fail_output="$tmpdir/fail.out"
if ADB="$fake_adb" ADB_LOG="$log" ADB_STATE=offline "$probe" "$tmpdir/offline.json" >"$fail_output" 2>&1; then
  echo 'FAIL: probe accepted offline device' >&2
  exit 1
fi
grep -q 'ADB device not ready: offline' "$fail_output"
if grep -q '^shell ' "$log"; then
  echo 'FAIL: probe issued shell command before rejecting offline device' >&2
  exit 1
fi

: > "$log"
output="$tmpdir/profile.json"
ADB="$fake_adb" ADB_LOG="$log" "$probe" "$output"
"$root/scripts/nethunter/validate_device_profile.sh" "$output"

if ! jq -e '
  .schema_version == 2 and
  .device.model == "ONEPLUS PKG110" and
  .device.codename == "pineapple" and
  .device.build_fingerprint == "oneplus/PKG110/PKG110:16/TEST/release-keys" and
  .kernel.release == "6.1.174-g638ecc425319" and
  .kernel.architecture == "aarch64" and
  .modules.wifi.sha256 == "abc123" and
  .modules.wifi.availability == "available" and
  .modules.bluetooth.vhci_name == "hci_vhci.ko" and
  .modules.bluetooth.manager == "enabled: true" and
  .modules.nfc.node == "crw-rw---- nfc nfc /dev/nq-nci" and
  .modules.nfc.availability == "available" and
  .usb.config == "mtp,adb" and
  .usb.functions == "mtp.gs0\nffs.adb" and
  .usb.availability == "available" and
  .gnss.service == "android.hardware.gnss.IGnss/default" and
  .gnss.availability == "available" and
  .nethunter.rootfs == "present"
' "$output" >/dev/null; then
  jq . "$output" >&2
  exit 1
fi

if grep -E '(^| )(svc|stop|start|insmod|rmmod|setprop|mount|umount|rm|cp|mv|dd)( |$)' "$log" >/dev/null; then
  echo 'FAIL: probe issued a state-changing remote command' >&2
  exit 1
fi

echo 'NetHunter device probe tests passed'
