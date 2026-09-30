#!/usr/bin/env bash
set -euo pipefail

ADB="${ADB:-adb}"
output="${1:-docs/nethunter/device-profile.json}"

state=$("$ADB" get-state 2>/dev/null | tr -d '\r' || true)
[[ "$state" == device ]] || {
  printf 'ADB device not ready: %s\n' "${state:-unavailable}" >&2
  exit 1
}

redact() { sed -E 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/xx:xx:xx:xx:xx:xx/g'; }
capture() { "$ADB" shell "$1" | tr -d '\r' | redact; }
capture_optional() { capture "$1" 2>/dev/null || true; }
availability() { [[ -n "$1" ]] && printf available || printf unavailable; }

model=$(capture 'getprop ro.product.model')
codename=$(capture 'getprop ro.product.device')
build_fingerprint=$(capture 'getprop ro.build.fingerprint')
vendor_fingerprint=$(capture_optional 'getprop ro.vendor.build.fingerprint')
incremental=$(capture_optional 'getprop ro.build.version.incremental')
slot_suffix=$(capture_optional 'getprop ro.boot.slot_suffix')
kernel_release=$(capture 'cat /proc/sys/kernel/osrelease 2>/dev/null || uname -r')
kernel_version=$(capture 'cat /proc/version')
selinux=$(capture_optional 'getenforce')
architecture=$(capture 'uname -m')
rootfs=$(capture_optional 'test -d /data/local/nhsystem && echo present || echo absent')

wifi_modules=$(capture_optional 'cat /proc/modules')
wifi_sha_raw=$(capture_optional 'sha256sum /vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko')
wifi_sha256=${wifi_sha_raw%% *}
[[ "$wifi_sha256" == "$wifi_sha_raw" ]] && wifi_sha256=""
wifi_modinfo=$(capture_optional 'command -v modinfo >/dev/null 2>&1 && modinfo /vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko || true')
wifi_con_mode=$(capture_optional 'cat /sys/module/qca_cld3_kiwi_v2/parameters/con_mode 2>/dev/null || true')
wifi_interfaces=$(capture_optional 'iw dev 2>/dev/null || true')
wifi_phys=$(capture_optional 'iw phy 2>/dev/null || true')
wifi_availability=$(availability "$wifi_sha256")

bt_rfkill=$(capture_optional 'rfkill list 2>/dev/null || true')
bt_manager=$(capture_optional 'dumpsys bluetooth_manager 2>/dev/null || true')
bt_services=$(capture_optional 'service list 2>/dev/null | grep -i bluetooth || true')
bt_device_node=$(capture_optional 'ls -l /dev/vhci 2>/dev/null || true')
bt_service_state=$(capture_optional 'getprop init.svc.bluetooth 2>/dev/null || true')
bt_availability=unavailable
if [[ -n "$bt_rfkill$bt_manager$bt_services" ]]; then bt_availability=available; fi

nfc_path=/vendor_dlkm/lib/modules/nxp-nci.ko
nfc_driver=$(capture_optional 'modinfo /vendor_dlkm/lib/modules/nxp-nci.ko 2>/dev/null || true')
nfc_node=$(capture_optional 'ls -l /dev/nq-nci 2>/dev/null || true')
nfc_state=$(capture_optional 'dumpsys nfc 2>/dev/null || true')
nfc_props=$(capture_optional 'getprop | grep -i nfc || true')
nfc_hal_service=$(capture_optional 'getprop init.svc.vendor.nfc_hal_service 2>/dev/null || true')
nfc_availability=$(availability "$nfc_node")

usb_config=$(capture_optional 'getprop sys.usb.config')
usb_roles=$(capture_optional 'for role in /sys/class/usb_role/*/role; do [ -r "$role" ] && printf "%s=%s\n" "$role" "$(cat "$role")"; done')
usb_gadgets=$(capture_optional 'ls -1 /config/usb_gadget 2>/dev/null || true')
udcs=$(capture_optional 'for udc in /sys/class/udc/*; do [ -e "$udc" ] && basename "$udc"; done')
usb_functions=$(capture_optional 'ls -1 /config/usb_gadget/g1/functions 2>/dev/null || true')
usb_availability=unavailable
if [[ -n "$usb_gadgets$udcs" ]]; then usb_availability=available; fi

gnss_service=$(capture_optional 'service list 2>/dev/null | grep -i gnss || true')
gnss_location=$(capture_optional 'dumpsys location 2>/dev/null || true')
gnss_availability=$(availability "$gnss_service")

mkdir -p "$(dirname "$output")"
tmp=$(mktemp "${output}.tmp.XXXXXX")
trap 'rm -f "$tmp"' EXIT

jq -n \
  --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg model "$model" \
  --arg codename "$codename" \
  --arg build_fingerprint "$build_fingerprint" \
  --arg vendor_fingerprint "$vendor_fingerprint" \
  --arg incremental "$incremental" \
  --arg slot_suffix "$slot_suffix" \
  --arg kernel_release "$kernel_release" \
  --arg kernel_version "$kernel_version" \
  --arg selinux "$selinux" \
  --arg architecture "$architecture" \
  --arg rootfs "$rootfs" \
  --arg wifi_modules "$wifi_modules" \
  --arg wifi_sha256 "$wifi_sha256" \
  --arg wifi_modinfo "$wifi_modinfo" \
  --arg wifi_con_mode "$wifi_con_mode" \
  --arg wifi_interfaces "$wifi_interfaces" \
  --arg wifi_phys "$wifi_phys" \
  --arg wifi_availability "$wifi_availability" \
  --arg bt_rfkill "$bt_rfkill" \
  --arg bt_manager "$bt_manager" \
  --arg bt_services "$bt_services" \
  --arg bt_device_node "$bt_device_node" \
  --arg bt_service_state "$bt_service_state" \
  --arg bt_availability "$bt_availability" \
  --arg nfc_driver "$nfc_driver" \
  --arg nfc_node "$nfc_node" \
  --arg nfc_state "$nfc_state" \
  --arg nfc_props "$nfc_props" \
  --arg nfc_hal_service "$nfc_hal_service" \
  --arg nfc_availability "$nfc_availability" \
  --arg usb_config "$usb_config" \
  --arg usb_roles "$usb_roles" \
  --arg usb_gadgets "$usb_gadgets" \
  --arg udcs "$udcs" \
  --arg usb_functions "$usb_functions" \
  --arg usb_availability "$usb_availability" \
  --arg gnss_service "$gnss_service" \
  --arg gnss_location "$gnss_location" \
  --arg gnss_availability "$gnss_availability" \
  '{
    schema_version: 2,
    created_at: $created_at,
    device: {
      model: $model,
      codename: $codename,
      build_fingerprint: $build_fingerprint,
      vendor_build_fingerprint: $vendor_fingerprint,
      incremental: $incremental,
      slot_suffix: $slot_suffix
    },
    kernel: {
      release: $kernel_release,
      version: $kernel_version,
      selinux: $selinux,
      architecture: $architecture
    },
    nethunter: {rootfs: $rootfs},
    modules: {
      wifi: {
        path: "/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko",
        sha256: $wifi_sha256,
        modinfo: $wifi_modinfo,
        loaded: $wifi_modules,
        con_mode: $wifi_con_mode,
        interfaces: $wifi_interfaces,
        phys: $wifi_phys,
        availability: $wifi_availability
      },
      bluetooth: {
        vhci_name: "hci_vhci.ko",
        device_node: $bt_device_node,
        rfkill: $bt_rfkill,
        manager: $bt_manager,
        services: ($bt_services + "\nservice_state=" + $bt_service_state),
        availability: $bt_availability
      },
      nfc: {
        path: "/vendor_dlkm/lib/modules/nxp-nci.ko",
        driver: $nfc_driver,
        node: $nfc_node,
        state: $nfc_state,
        properties: $nfc_props,
        hal_service: $nfc_hal_service,
        availability: $nfc_availability
      }
    },
    usb: {
      config: $usb_config,
      roles: $usb_roles,
      gadgets: $usb_gadgets,
      udcs: $udcs,
      functions: $usb_functions,
      availability: $usb_availability
    },
    gnss: {
      service: $gnss_service,
      location_dump: $gnss_location,
      availability: $gnss_availability
    }
  }' > "$tmp"

mv "$tmp" "$output"
trap - EXIT
printf 'Wrote device profile: %s\n' "$output"
