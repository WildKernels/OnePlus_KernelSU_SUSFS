#!/usr/bin/env bash
set -euo pipefail

ADB="${ADB:-adb}"
output="${1:-docs/nethunter/device-profile.json}"

state=$("$ADB" get-state 2>/dev/null || true)
[[ "$state" == device ]] || {
  printf 'ADB device not ready: %s\n' "${state:-unavailable}" >&2
  exit 1
}

capture() {
  "$ADB" shell "$1"
}

model=$(capture 'getprop ro.product.model')
device=$(capture 'getprop ro.product.device')
build_fingerprint=$(capture 'getprop ro.build.fingerprint')
vendor_fingerprint=$(capture 'getprop ro.vendor.build.fingerprint')
incremental=$(capture 'getprop ro.build.version.incremental')
slot_suffix=$(capture 'getprop ro.boot.slot_suffix')
release=$(capture 'uname -r')
version=$(capture 'cat /proc/version')
selinux=$(capture 'getenforce')
architecture=$(capture 'uname -m')
rootfs=$(capture 'test -d /data/local/nhsystem && echo present || echo absent')
wifi_modules=$(capture 'cat /proc/modules')
wifi_sha256=$(capture 'sha256sum /vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko')
wifi_modinfo=$(capture 'command -v modinfo >/dev/null 2>&1 && modinfo /vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko || true')
wifi_con_mode=$(capture 'cat /sys/module/qca_cld3_kiwi_v2/parameters/con_mode 2>/dev/null || true')
wifi_interfaces=$(capture 'iw dev 2>/dev/null || true')
wifi_phys=$(capture 'iw phy 2>/dev/null || true')
bt_rfkill=$(capture 'rfkill list 2>/dev/null || true')
bt_manager=$(capture 'dumpsys bluetooth_manager 2>/dev/null || true')
bt_services=$(capture 'service list 2>/dev/null | grep -i bluetooth || true')
nfc_node=$(capture 'ls -l /dev/nq-nci 2>/dev/null || true')
nfc_state=$(capture 'dumpsys nfc 2>/dev/null || true')
nfc_props=$(capture 'getprop | grep -i nfc || true')
usb_config=$(capture 'getprop sys.usb.config')
usb_roles=$(capture 'for role in /sys/class/usb_role/*/role; do [ -r "$role" ] && printf "%s=%s\n" "$role" "$(cat "$role")"; done')
usb_gadgets=$(capture 'ls -1 /config/usb_gadget 2>/dev/null || true')
udcs=$(capture 'for udc in /sys/class/udc/*; do [ -e "$udc" ] && basename "$udc"; done')

mkdir -p "$(dirname "$output")"
tmp=$(mktemp "${output}.tmp.XXXXXX")
trap 'rm -f "$tmp"' EXIT

jq -n \
  --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg model "$model" \
  --arg device "$device" \
  --arg build_fingerprint "$build_fingerprint" \
  --arg vendor_fingerprint "$vendor_fingerprint" \
  --arg incremental "$incremental" \
  --arg slot_suffix "$slot_suffix" \
  --arg release "$release" \
  --arg version "$version" \
  --arg selinux "$selinux" \
  --arg architecture "$architecture" \
  --arg rootfs "$rootfs" \
  --arg wifi_modules "$wifi_modules" \
  --arg wifi_sha256 "$wifi_sha256" \
  --arg wifi_modinfo "$wifi_modinfo" \
  --arg wifi_con_mode "$wifi_con_mode" \
  --arg wifi_interfaces "$wifi_interfaces" \
  --arg wifi_phys "$wifi_phys" \
  --arg bt_rfkill "$bt_rfkill" \
  --arg bt_manager "$bt_manager" \
  --arg bt_services "$bt_services" \
  --arg nfc_node "$nfc_node" \
  --arg nfc_state "$nfc_state" \
  --arg nfc_props "$nfc_props" \
  --arg usb_config "$usb_config" \
  --arg usb_roles "$usb_roles" \
  --arg usb_gadgets "$usb_gadgets" \
  --arg udcs "$udcs" \
  '{
    schema_version: 1,
    created_at: $created_at,
    device: {
      model: $model,
      device: $device,
      build_fingerprint: $build_fingerprint,
      vendor_fingerprint: $vendor_fingerprint,
      incremental: $incremental,
      slot_suffix: $slot_suffix
    },
    kernel: {
      release: $release,
      version: $version,
      selinux: $selinux,
      architecture: $architecture
    },
    nethunter: {rootfs: $rootfs},
    wifi: {
      modules: $wifi_modules,
      module: {path: "/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko", sha256: $wifi_sha256, modinfo: $wifi_modinfo},
      con_mode: $wifi_con_mode,
      interfaces: $wifi_interfaces,
      phys: $wifi_phys
    },
    bluetooth: {rfkill: $bt_rfkill, manager: $bt_manager, services: $bt_services},
    nfc: {node: $nfc_node, state: $nfc_state, properties: $nfc_props},
    usb: {config: $usb_config, roles: $usb_roles, gadgets: $usb_gadgets, udcs: $udcs}
  }' > "$tmp"

mv "$tmp" "$output"
trap - EXIT
printf 'Wrote device profile: %s\n' "$output"
