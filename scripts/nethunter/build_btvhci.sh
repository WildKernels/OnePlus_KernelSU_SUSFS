#!/usr/bin/env bash
# Export hci_vhci.ko built by the same full kernel build as the Image.
set -euo pipefail

[[ $# -eq 4 ]] || {
  echo "Usage: $0 <OP-ACE-5|OP-ACE-5-6.1.118> <kernel_source_root> <common_out> <output_dir>" >&2
  exit 2
}

target="$1"
kernel_src=$(realpath -m "$2")
common_out=$(realpath -m "$3")
output_dir=$(realpath -m "$4")
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

bash "$script_dir/build_target_modules.sh" --validate-only \
  "$target" "$kernel_src" "$common_out" "$output_dir"

grep -qx 'CONFIG_BT=m' "$common_out/.config" || { echo "ERROR: CONFIG_BT=m required" >&2; exit 1; }
grep -qx 'CONFIG_BT_HCIVHCI=m' "$common_out/.config" || { echo "ERROR: CONFIG_BT_HCIVHCI=m required" >&2; exit 1; }
grep -qx 'CONFIG_MODVERSIONS=y' "$common_out/.config" || { echo "ERROR: CONFIG_MODVERSIONS=y required" >&2; exit 1; }

ko=""
for install_root in "$common_out/nh-install/lib/modules" "$common_out/install/lib/modules"; do
  if [[ -d "$install_root" ]]; then
    ko=$(find "$install_root" -type f -path '*/kernel/drivers/bluetooth/hci_vhci.ko' -print -quit)
    [[ -n "$ko" ]] && break
  fi
done
[[ -n "$ko" ]] || ko="$common_out/drivers/bluetooth/hci_vhci.ko"
[[ -s "$ko" ]] || { echo "ERROR: hci_vhci.ko missing; build kernel with target modules enabled" >&2; exit 1; }
file "$ko" | grep -q 'ELF 64-bit.*ARM aarch64' || { echo "ERROR: hci_vhci.ko is not AArch64" >&2; exit 1; }
command -v modinfo >/dev/null 2>&1 || { echo "ERROR: modinfo required" >&2; exit 1; }
[[ "$(modinfo -F name "$ko")" == hci_vhci ]] || { echo "ERROR: unexpected VHCI module name" >&2; exit 1; }

mkdir -p "$output_dir"
cp "$ko" "$output_dir/hci_vhci.ko"
jq -n \
  --arg target "$target" \
  --arg config_sha256 "$(sha256sum "$common_out/.config" | cut -d' ' -f1)" \
  --arg module_symvers_sha256 "$(sha256sum "$common_out/Module.symvers" | cut -d' ' -f1)" \
  --arg name "$(modinfo -F name "$output_dir/hci_vhci.ko")" \
  --arg vermagic "$(modinfo -F vermagic "$output_dir/hci_vhci.ko")" \
  --arg signer "$(modinfo -F signer "$output_dir/hci_vhci.ko" 2>/dev/null || true)" \
  --arg sig_id "$(modinfo -F sig_id "$output_dir/hci_vhci.ko" 2>/dev/null || true)" \
  --arg depends "$(modinfo -F depends "$output_dir/hci_vhci.ko")" \
  --arg sha256 "$(sha256sum "$output_dir/hci_vhci.ko" | cut -d' ' -f1)" \
  '{target:$target,name:$name,config_sha256:$config_sha256,module_symvers_sha256:$module_symvers_sha256,vermagic:$vermagic,signer:$signer,sig_id:$sig_id,depends:$depends,sha256:$sha256}' \
  > "$output_dir/hci-vhci-evidence.json"

echo "Exported hci_vhci.ko: $output_dir/hci_vhci.ko"
