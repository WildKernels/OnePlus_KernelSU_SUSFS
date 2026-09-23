#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--validate-only] <OP-ACE-5|OP-ACE-5-6.1.118> <kernel_source_root> <common_out> <output_dir>" >&2
  exit 2
}

validate_only=0
if [[ "${1:-}" == --validate-only ]]; then
  validate_only=1
  shift
fi
[[ $# -eq 4 ]] || usage

target="$1"
kernel_src=$(realpath -m "$2")
common_out=$(realpath -m "$3")
output_dir=$(realpath -m "$4")

case "$target" in
  OP-ACE-5)
    expected_common=086936b3387b4018805500fa4069d09637fdb89b
    expected_modules=21a5694f721d3826ac9e101e5d65919f2a8e739e
    ;;
  OP-ACE-5-6.1.118)
    expected_common=7499247fd6e0669a062ec44cce948ec1e9d4c75e
    expected_modules=d5323ede4f2059880c54818abfc1ac22d7e8bd5f
    ;;
  *) echo "ERROR: Unknown target: $target" >&2; exit 1 ;;
esac

manifest="$kernel_src/manifest.xml"
[[ -f "$manifest" ]] || { echo "ERROR: source manifest missing: $manifest" >&2; exit 1; }
common_src="$kernel_src/kernel_platform/common"
[[ -f "$common_src/Makefile" ]] || { echo "ERROR: common kernel source missing: $common_src" >&2; exit 1; }
[[ -f "$common_out/.config" ]] || { echo "ERROR: common kernel .config missing: $common_out/.config" >&2; exit 1; }
[[ -s "$common_out/Module.symvers" ]] || { echo "ERROR: full-build Module.symvers missing: $common_out/Module.symvers" >&2; exit 1; }

python3 - "$manifest" "$expected_common" "$expected_modules" <<'PY'
import sys
import xml.etree.ElementTree as ET

manifest, expected_common, expected_modules = sys.argv[1:]
try:
    root = ET.parse(manifest).getroot()
except (OSError, ET.ParseError) as exc:
    raise SystemExit(f"ERROR: invalid source manifest: {exc}")

projects = {project.get("name"): project for project in root.findall("project")}
expected = {
    "android_kernel_common_oneplus_sm8650": (expected_common, "kernel_platform/common"),
    "android_kernel_modules_and_devicetree_oneplus_sm8650": (expected_modules, "./"),
}
for name, (revision, path) in expected.items():
    project = projects.get(name)
    if project is None:
        raise SystemExit(f"ERROR: source manifest missing project {name}")
    actual = project.get("revision", "")
    if actual != revision:
        raise SystemExit(f"ERROR: {name} revision mismatch: got {actual}, expected {revision}")
    actual_path = project.get("path", name)
    if actual_path != path:
        raise SystemExit(f"ERROR: {name} path mismatch: got {actual_path}, expected {path}")
PY

grep -q '^CONFIG_MODVERSIONS=y$' "$common_out/.config" || {
  echo "ERROR: target .config must enable CONFIG_MODVERSIONS=y" >&2
  exit 1
}

hci_ko="$common_out/drivers/bluetooth/hci_vhci.ko"
if [[ -f "$hci_ko" ]]; then
  if ! file "$hci_ko" | grep -q 'ELF 64-bit.*ARM aarch64'; then
    echo "ERROR: hci_vhci.ko is not AArch64: $hci_ko" >&2
    exit 1
  fi
  if command -v modinfo >/dev/null 2>&1 && [[ "$(modinfo -F name "$hci_ko")" != hci_vhci ]]; then
    echo "ERROR: unexpected module name in $hci_ko" >&2
    exit 1
  fi
fi

if [[ "$validate_only" == 1 ]]; then
  echo "Build inputs valid for $target"
  echo "common_revision=$expected_common"
  echo "modules_revision=$expected_modules"
  exit 0
fi

grep -q '^CONFIG_BT_HCIVHCI=m$' "$common_out/.config" || {
  echo "ERROR: CONFIG_BT_HCIVHCI=m is required; enable NetHunter modules before kernel build" >&2
  exit 1
}
[[ -f "$hci_ko" ]] || {
  echo "ERROR: hci_vhci.ko missing; run full 'make Image modules' in kernel build action" >&2
  exit 1
}

bash "$(dirname "$0")/build_btvhci.sh" \
  "$target" "$kernel_src" "$common_out" "$output_dir"
bash "$(dirname "$0")/build_stock_wifi.sh" \
  "$target" "$kernel_src" "$common_out" "$output_dir"

if [[ -n "${NH_NXP_NCI_DIR:-}" ]]; then
  bash "$(dirname "$0")/build_nxp_nci.sh" \
    "$target" "$kernel_src" "$common_out" "$output_dir"
fi

for name in hci_vhci.ko qca_cld3_kiwi_v2.ko; do
  [[ -s "$output_dir/$name" ]] || { echo "ERROR: required module output missing: $name" >&2; exit 1; }
  file "$output_dir/$name" | grep -q 'ELF 64-bit.*ARM aarch64' || {
    echo "ERROR: $name is not AArch64" >&2
    exit 1
  }
done

nfc_evidence='{"status":"not_built","reason":"NXP driver source path not mapped"}'
if [[ -s "$output_dir/nxp-nci-evidence.json" ]]; then
  nfc_evidence=$(<"$output_dir/nxp-nci-evidence.json")
fi

jq -n \
  --arg target "$target" \
  --arg common_revision "$expected_common" \
  --arg modules_revision "$expected_modules" \
  --arg config_sha256 "$(sha256sum "$common_out/.config" | cut -d' ' -f1)" \
  --arg symvers_sha256 "$(sha256sum "$common_out/Module.symvers" | cut -d' ' -f1)" \
  --slurpfile hci "$output_dir/hci-vhci-evidence.json" \
  --slurpfile wifi "$output_dir/wifi-stock-evidence.json" \
  --argjson nfc "$nfc_evidence" \
  '{target:$target, source:{common:$common_revision,modules:$modules_revision}, config_sha256:$config_sha256, module_symvers_sha256:$symvers_sha256, modules:{hci_vhci:$hci[0],wifi_stock:$wifi[0],nxp_nci:$nfc}}' \
  > "$output_dir/build-evidence.json"

echo "Built target modules for $target in $output_dir"
