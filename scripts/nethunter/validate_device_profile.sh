#!/usr/bin/env bash
set -euo pipefail

profile=${1:?usage: validate_device_profile.sh <profile.json>}

jq empty "$profile" >/dev/null 2>&1 || {
  printf 'Invalid JSON profile: %s\n' "$profile" >&2
  exit 1
}

check() {
  local path="$1" filter="$2"
  if ! jq -e "$filter" "$profile" >/dev/null 2>&1; then
    printf 'Invalid device profile field: %s\n' "$path" >&2
    exit 1
  fi
}

check schema_version '.schema_version == 2'
check created_at '(.created_at | type == "string" and length > 0)'
check device.model '(.device.model | type == "string" and length > 0)'
check device.codename '(.device.codename | type == "string" and length > 0)'
check device.build_fingerprint '(.device.build_fingerprint | type == "string" and length > 0)'
check kernel.release '(.kernel.release | type == "string" and length > 0)'
check kernel.architecture '.kernel.architecture == "aarch64"'
check nethunter.rootfs '(.nethunter.rootfs | type == "string")'
check modules.wifi.path '.modules.wifi.path == "/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko"'
check modules.wifi.sha256 'if .modules.wifi.availability == "available" then (.modules.wifi.sha256 | type == "string" and length > 0) else (.modules.wifi.sha256 | type == "string") end'
check modules.wifi.modinfo '(.modules.wifi.modinfo | type == "string")'
check modules.wifi.loaded '(.modules.wifi.loaded | type == "string")'
check modules.wifi.con_mode '(.modules.wifi.con_mode | type == "string")'
check modules.wifi.interfaces '(.modules.wifi.interfaces | type == "string")'
check modules.wifi.phys '(.modules.wifi.phys | type == "string")'
check modules.wifi.availability '(.modules.wifi.availability == "available" or .modules.wifi.availability == "unavailable" or .modules.wifi.availability == "unknown")'
check modules.bluetooth.vhci_name '.modules.bluetooth.vhci_name == "hci_vhci.ko"'
check modules.bluetooth.device_node '(.modules.bluetooth.device_node | type == "string")'
check modules.bluetooth.rfkill '(.modules.bluetooth.rfkill | type == "string")'
check modules.bluetooth.manager '(.modules.bluetooth.manager | type == "string")'
check modules.bluetooth.services '(.modules.bluetooth.services | type == "string")'
check modules.bluetooth.availability '(.modules.bluetooth.availability == "available" or .modules.bluetooth.availability == "unavailable" or .modules.bluetooth.availability == "unknown")'
check modules.nfc.path '.modules.nfc.path == "/vendor_dlkm/lib/modules/nxp-nci.ko"'
check modules.nfc.driver '(.modules.nfc.driver | type == "string")'
check modules.nfc.node '(.modules.nfc.node | type == "string")'
check modules.nfc.state '(.modules.nfc.state | type == "string")'
check modules.nfc.properties '(.modules.nfc.properties | type == "string")'
check modules.nfc.hal_service '(.modules.nfc.hal_service | type == "string")'
check modules.nfc.availability '(.modules.nfc.availability == "available" or .modules.nfc.availability == "unavailable" or .modules.nfc.availability == "unknown")'
check usb.config '(.usb.config | type == "string")'
check usb.roles '(.usb.roles | type == "string")'
check usb.gadgets '(.usb.gadgets | type == "string")'
check usb.udcs '(.usb.udcs | type == "string")'
check usb.functions '(.usb.functions | type == "string")'
check usb.availability '(.usb.availability == "available" or .usb.availability == "unavailable" or .usb.availability == "unknown")'
check gnss.service 'if .gnss.availability == "available" then (.gnss.service | type == "string" and length > 0) else (.gnss.service | type == "string") end'
check gnss.location_dump '(.gnss.location_dump | type == "string")'
check gnss.availability '(.gnss.availability == "available" or .gnss.availability == "unavailable" or .gnss.availability == "unknown")'

printf 'Device profile valid: %s\n' "$profile"
