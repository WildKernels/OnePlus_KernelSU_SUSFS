#!/usr/bin/env bash
# Build stock nxp-nci.ko, then optional patched copy without editing synced source.
set -euo pipefail

usage() {
  echo "Usage: $0 <OP-ACE-5|OP-ACE-5-6.1.118> <kernel_source_root> <common_out> <output_dir> [--patched-source <patch_file>]" >&2
  exit 2
}

[[ $# -ge 4 ]] || usage
target="$1"
kernel_src=$(realpath -m "$2")
common_out=$(realpath -m "$3")
output_dir=$(realpath -m "$4")
shift 4
patch_file=""
if [[ $# -gt 0 ]]; then
  [[ $# -eq 2 && "$1" == --patched-source ]] || usage
  patch_file=$(realpath -m "$2")
  [[ -f "$patch_file" ]] || { echo "ERROR: NFC driver patch missing: $patch_file" >&2; exit 1; }
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$script_dir/build_target_modules.sh" --validate-only \
  "$target" "$kernel_src" "$common_out" "$output_dir"

driver_src="${NH_NXP_NCI_DIR:-$kernel_src/vendor/nxp/opensource/driver}"
driver_src=$(realpath -m "$driver_src")
case "$driver_src" in
  "$kernel_src"/*) ;;
  *) echo "ERROR: NFC driver source must be inside the pinned kernel workspace" >&2; exit 1 ;;
esac
[[ -f "$driver_src/Kbuild" && -f "$driver_src/config/gki_nfc.conf" ]] || {
  echo "ERROR: expected NXP driver Kbuild/config missing under $driver_src" >&2
  exit 1
}
[[ -s "$common_out/Module.symvers" ]] || { echo "ERROR: full-build Module.symvers required" >&2; exit 1; }
common_src="$kernel_src/kernel_platform/common"
build_root=$(mktemp -d "${TMPDIR:-/tmp}/nh-nxp-nci.XXXXXX")
trap 'rm -rf "$build_root"' EXIT

# The NXP driver depends on Qualcomm/OnePlus techpack headers that the
# manifest-synced trees do not carry. Require the caller to stage them.
for header in include/linux/ipc_logging.h include/linux/pinctrl/qcom-pinctrl.h; do
  [[ -f "$common_src/$header" ]] || {
    echo "ERROR: missing techpack header $common_src/$header" >&2
    echo "       stage it from OnePlusOSS/android_kernel_oneplus_sm8650 before building" >&2
    exit 1
  }
done
if [[ ! -e "$common_src/include/soc/oplus/boot/boot_mode.h" ]]; then
  mkdir -p "$common_src/include/soc/oplus"
  ln -sfn ../../../../../vendor/oplus/kernel/boot/include \
    "$common_src/include/soc/oplus/boot"
fi

normalize_driver_source() {
  local staged_driver="$1"
  # Vendor Kbuild contains C preprocessor #ifdef lines that break make.
  python3 - "$staged_driver/Kbuild" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace(
    "\t\tnfc/i2c_drv.o \\\n#ifdef CONFIG_NXP_NFC_VBAT_MONITOR\n               nfc_vbat_monitor.o\n#endif",
    "\t\tnfc/i2c_drv.o \\\n\t\tnfc/nfc_vbat_monitor.o",
)
text = text.replace(
    "#ifdef CONFIG_NXP_NFC_VBAT_MONITOR\nccflags-y += -DCONFIG_NXP_NFC_VBAT_MONITOR\n#endif",
    "ccflags-y += -DCONFIG_NXP_NFC_VBAT_MONITOR",
)
open(path, "w").write(text)
PY
  # Vendor format strings pass size_t to %d; -Werror turns them into errors.
  python3 - "$staged_driver/nfc/i2c_drv.c" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace('"%s of %d bytes, ret %d", __func__, count',
                    '"%s of %zu bytes, ret %d", __func__, count')
text = text.replace('"%s sending %d B", __func__, count',
                    '"%s sending %zu B", __func__, count')
open(path, "w").write(text)
PY
}

mkdir -p "$output_dir"

stage_driver() {
  local stage="$1" apply_patch_file="${2:-}" staged_driver
  staged_driver="$stage/vendor/nxp/opensource/driver"
  mkdir -p "$(dirname "$staged_driver")" "$stage/vendor"
  cp -a "$driver_src" "$staged_driver"
  ln -s "$kernel_src/vendor/qcom" "$stage/vendor/qcom"
  if [[ -n "$apply_patch_file" ]]; then
    git -C "$stage" init -q
    git -C "$stage" add vendor/nxp/opensource/driver
    git -C "$stage" apply --check "$apply_patch_file"
    git -C "$stage" apply "$apply_patch_file"
  fi
  printf '%s\n' "$staged_driver"
}

build_driver() {
  local stage="$1" artifact="$2" label="$3" apply_patch_file="${4:-}"
  local driver install_root ko module_name driver_revision patched_json evidence_name
  driver=$(stage_driver "$stage" "$apply_patch_file")
  normalize_driver_source "$driver"
  install_root="$stage/install"
  make -C "$common_src" O="$common_out" M="$driver" NFC_ROOT="$driver" \
    KBUILD_MODPOST_WARN=1 modules
  make -C "$common_src" O="$common_out" M="$driver" NFC_ROOT="$driver" \
    KBUILD_MODPOST_WARN=1 INSTALL_MOD_PATH="$install_root" modules_install
  ko=$(find "$install_root/lib/modules" -type f \( -name nxp-nci.ko -o -name nxp_nci.ko \) -print -quit 2>/dev/null || true)
  [[ -n "$ko" ]] || { echo "ERROR: installable nxp-nci.ko missing for $label build" >&2; return 1; }
  file "$ko" | grep -q 'ELF 64-bit.*ARM aarch64' || { echo "ERROR: nxp-nci.ko is not AArch64" >&2; return 1; }
  command -v modinfo >/dev/null 2>&1 || { echo "ERROR: modinfo required" >&2; return 1; }
  module_name=$(modinfo -F name "$ko")
  case "$module_name" in nxp-nci|nxp_nci) ;; *) echo "ERROR: unexpected NXP NFC module name: $module_name" >&2; return 1 ;; esac

  driver_revision=$(python3 - "$kernel_src/manifest.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
for project in root.findall("project"):
    if project.get("name") == "android_kernel_modules_and_devicetree_oneplus_sm8650":
        print(project.get("revision", ""))
        break
else:
    raise SystemExit("modules/device-tree project missing in source manifest")
PY
  ) || { echo "ERROR: NFC driver revision missing from manifest" >&2; return 1; }

  cp "$ko" "$output_dir/$artifact"
  [[ "$label" == patched ]] && patched_json=true || patched_json=false
  if [[ "$patched_json" == true ]]; then evidence_name=nxp-nci-patched-evidence.json; else evidence_name=nxp-nci-evidence.json; fi
  jq -n \
    --arg target "$target" \
    --arg driver_revision "$driver_revision" \
    --arg module_name "$module_name" \
    --arg config_sha256 "$(sha256sum "$common_out/.config" | cut -d' ' -f1)" \
    --arg module_symvers_sha256 "$(sha256sum "$common_out/Module.symvers" | cut -d' ' -f1)" \
    --arg vermagic "$(modinfo -F vermagic "$output_dir/$artifact")" \
    --arg signer "$(modinfo -F signer "$output_dir/$artifact" 2>/dev/null || true)" \
    --arg sig_id "$(modinfo -F sig_id "$output_dir/$artifact" 2>/dev/null || true)" \
    --arg depends "$(modinfo -F depends "$output_dir/$artifact")" \
    --arg sha256 "$(sha256sum "$output_dir/$artifact" | cut -d' ' -f1)" \
    --argjson patched "$patched_json" \
    '{target:$target,driver_revision:$driver_revision,module_name:$module_name,config_sha256:$config_sha256,module_symvers_sha256:$module_symvers_sha256,vermagic:$vermagic,signer:$signer,sig_id:$sig_id,depends:$depends,sha256:$sha256,patched:$patched}' \
    > "$output_dir/$evidence_name"
}

if [[ -n "$patch_file" ]]; then
  build_driver "$build_root/stock" nxp-nci-stock.ko stock
  build_driver "$build_root/patched" nxp-nci.ko patched "$patch_file"
else
  build_driver "$build_root/stock" nxp-nci.ko stock
fi

echo "NXP NFC module build complete for $target"
