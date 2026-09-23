#!/usr/bin/env bash
# Build unmodified Kiwi-v2 module as exact-KMI baseline.
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
common_src="$kernel_src/kernel_platform/common"
wlan_dir="$kernel_src/vendor/qcom/opensource/wlan/qcacld-3.0"

bash "$script_dir/build_target_modules.sh" --validate-only \
  "$target" "$kernel_src" "$common_out" "$output_dir"
[[ -d "$wlan_dir" ]] || { echo "ERROR: Kiwi-v2 WLAN source missing: $wlan_dir" >&2; exit 1; }
[[ -f "$wlan_dir/Makefile" ]] || { echo "ERROR: qcacld-3.0 Makefile missing: $wlan_dir/Makefile" >&2; exit 1; }

clang_dir="$kernel_src/kernel_platform/prebuilts/clang/host/linux-x86/clang-r487747c/bin"
if [[ -d "$clang_dir" ]]; then PATH="$clang_dir:$PATH"; export PATH; fi
export ARCH=arm64 LLVM=1 LLVM_IAS=1

echo "=== Build unmodified qca_cld3_kiwi_v2.ko ==="
echo "Target: $target"
echo "WLAN source: $wlan_dir"
echo "Kernel source: $common_src"
echo "Kernel output: $common_out"

make -C "$wlan_dir" \
  KERNEL_SRC="$common_src" \
  KERNEL_OUT="$common_out" \
  O="$common_out" \
  M="$wlan_dir" \
  WLAN_ROOT="$wlan_dir" \
  MODNAME=qca_cld3_kiwi_v2 \
  CONFIG_QCA_CLD_WLAN=m \
  KBUILD_EXTRA="CONFIG_CNSS_KIWI_V2=y CONFIG_QCA_WIFI_KIWI=y CONFIG_KIWI_HEADERS_DEF=y" \
  modules

mkdir -p "$output_dir"
install_root="$output_dir/wifi-install"
make -C "$wlan_dir" \
  KERNEL_SRC="$common_src" \
  KERNEL_OUT="$common_out" \
  O="$common_out" \
  M="$wlan_dir" \
  WLAN_ROOT="$wlan_dir" \
  MODNAME=qca_cld3_kiwi_v2 \
  CONFIG_QCA_CLD_WLAN=m \
  KBUILD_EXTRA="CONFIG_CNSS_KIWI_V2=y CONFIG_QCA_WIFI_KIWI=y CONFIG_KIWI_HEADERS_DEF=y" \
  INSTALL_MOD_PATH="$install_root" \
  modules_install

ko=$(find "$install_root/lib/modules" -type f -name qca_cld3_kiwi_v2.ko -print -quit 2>/dev/null || true)
[[ -n "$ko" ]] || { echo "ERROR: signed/installable qca_cld3_kiwi_v2.ko not produced by Kbuild modules_install" >&2; exit 1; }
file "$ko" | grep -q 'ELF 64-bit.*ARM aarch64' || {
  echo "ERROR: built Wi-Fi module is not AArch64: $ko" >&2
  exit 1
}

command -v modinfo >/dev/null 2>&1 || { echo "ERROR: modinfo required" >&2; exit 1; }
mkdir -p "$output_dir"
cp "$ko" "$output_dir/qca_cld3_kiwi_v2.ko"
name=$(modinfo -F name "$output_dir/qca_cld3_kiwi_v2.ko")
[[ "$name" == qca_cld3_kiwi_v2 ]] || { echo "ERROR: unexpected Wi-Fi module name: $name" >&2; exit 1; }

case "$target" in
  OP-ACE-5) modules_revision=21a5694f721d3826ac9e101e5d65919f2a8e739e ;;
  OP-ACE-5-6.1.118) modules_revision=d5323ede4f2059880c54818abfc1ac22d7e8bd5f ;;
esac

jq -n \
  --arg target "$target" \
  --arg source_revision "$modules_revision" \
  --arg config_sha256 "$(sha256sum "$common_out/.config" | cut -d' ' -f1)" \
  --arg module_symvers_sha256 "$(sha256sum "$common_out/Module.symvers" | cut -d' ' -f1)" \
  --arg vermagic "$(modinfo -F vermagic "$output_dir/qca_cld3_kiwi_v2.ko")" \
  --arg signer "$(modinfo -F signer "$output_dir/qca_cld3_kiwi_v2.ko" 2>/dev/null || true)" \
  --arg sig_id "$(modinfo -F sig_id "$output_dir/qca_cld3_kiwi_v2.ko" 2>/dev/null || true)" \
  --arg depends "$(modinfo -F depends "$output_dir/qca_cld3_kiwi_v2.ko")" \
  --arg sha256 "$(sha256sum "$output_dir/qca_cld3_kiwi_v2.ko" | cut -d' ' -f1)" \
  '{target:$target,source_revision:$source_revision,config_sha256:$config_sha256,module_symvers_sha256:$module_symvers_sha256,vermagic:$vermagic,signer:$signer,sig_id:$sig_id,depends:$depends,sha256:$sha256,patched:false}' \
  > "$output_dir/wifi-stock-evidence.json"

echo "Built stock Wi-Fi module: $output_dir/qca_cld3_kiwi_v2.ko"
