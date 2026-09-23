#!/usr/bin/env bash
# Build stock nxp_nci.ko baseline. Patched driver source can be supplied later.
set -euo pipefail

usage() {
  echo "Usage: $0 <OP-ACE-5|OP-ACE-5-6.1.118> <kernel_source_root> <common_out> <output_dir> [--patched-source <driver_source_dir>]" >&2
  exit 2
}

[[ $# -ge 4 ]] || usage
common_out=$(realpath -m "$3")
output_dir=$(realpath -m "$4")
shift 4
driver_dir="${NH_NXP_NCI_DIR:-}"
patched=false
if [[ $# -gt 0 ]]; then
  [[ $# -eq 2 && "$1" == --patched-source ]] || usage
  driver_dir="$2"
  patched=true
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$script_dir/build_target_modules.sh" --validate-only \
  "$target" "$kernel_src" "$common_out" "$output_dir"

if [[ -z "$driver_dir" ]]; then
  echo "INFO: NXP NFC driver source path not configured; skipping optional baseline build" >&2
  exit 0
fi
driver_dir=$(realpath -m "$driver_dir")
case "$driver_dir" in
  "$kernel_src"/*) ;;
  *) echo "ERROR: NFC driver source must be inside the pinned kernel workspace" >&2; exit 1 ;;
esac
[[ -f "$driver_dir/Makefile" ]] || { echo "ERROR: NXP driver Makefile missing: $driver_dir/Makefile" >&2; exit 1; }

common_src="$kernel_src/kernel_platform/common"
[[ -s "$common_out/Module.symvers" ]] || { echo "ERROR: full-build Module.symvers required" >&2; exit 1; }
mkdir -p "$output_dir"
make -C "$common_src" O="$common_out" M="$driver_dir" modules
install_root="$output_dir/nfc-install"
make -C "$common_src" O="$common_out" M="$driver_dir" INSTALL_MOD_PATH="$install_root" modules_install

ko=$(find "$install_root/lib/modules" -type f \( -name nxp_nci.ko -o -name nxp-nci.ko \) -print -quit 2>/dev/null || true)
[[ -n "$ko" ]] || { echo "ERROR: installable nxp_nci.ko not produced by Kbuild" >&2; exit 1; }
file "$ko" | grep -q 'ELF 64-bit.*ARM aarch64' || { echo "ERROR: nxp_nci.ko is not AArch64" >&2; exit 1; }
command -v modinfo >/dev/null 2>&1 || { echo "ERROR: modinfo required" >&2; exit 1; }
[[ "$(modinfo -F name "$ko")" == nxp_nci ]] || { echo "ERROR: unexpected NFC module name" >&2; exit 1; }

mkdir -p "$output_dir"
cp "$ko" "$output_dir/nxp_nci.ko"
jq -n \
  --arg target "$target" \
  --arg driver_source "$driver_dir" \
  --arg config_sha256 "$(sha256sum "$common_out/.config" | cut -d' ' -f1)" \
  --arg module_symvers_sha256 "$(sha256sum "$common_out/Module.symvers" | cut -d' ' -f1)" \
  --arg vermagic "$(modinfo -F vermagic "$output_dir/nxp_nci.ko")" \
  --arg depends "$(modinfo -F depends "$output_dir/nxp_nci.ko")" \
  --arg sha256 "$(sha256sum "$output_dir/nxp_nci.ko" | cut -d' ' -f1)" \
  --argjson patched "$patched" \
  '{target:$target,driver_source:$driver_source,config_sha256:$config_sha256,module_symvers_sha256:$module_symvers_sha256,vermagic:$vermagic,depends:$depends,sha256:$sha256,patched:$patched}' \
  > "$output_dir/nxp-nci-evidence.json"

echo "Built nxp_nci baseline: $output_dir/nxp_nci.ko"
