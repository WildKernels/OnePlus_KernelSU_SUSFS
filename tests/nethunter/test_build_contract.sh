#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
builder="$root/scripts/nethunter/build_target_modules.sh"
wifi_builder="$root/scripts/nethunter/build_stock_wifi.sh"
nfc_builder="$root/scripts/nethunter/build_nxp_nci.sh"
vhci_builder="$root/scripts/nethunter/build_btvhci.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

[[ -x "$builder" ]] || { echo 'FAIL: build_target_modules.sh is missing' >&2; exit 1; }
[[ -x "$wifi_builder" ]] || { echo 'FAIL: build_stock_wifi.sh is missing' >&2; exit 1; }
[[ -x "$nfc_builder" ]] || { echo 'FAIL: build_nxp_nci.sh is missing' >&2; exit 1; }
[[ -x "$vhci_builder" ]] || { echo 'FAIL: build_btvhci.sh is missing' >&2; exit 1; }

workspace="$tmpdir/kernel"
common_out="$workspace/kernel_platform/common/out"
output="$tmpdir/out"
mkdir -p "$common_out"
printf '# fixture common kernel Makefile\n' > "$workspace/kernel_platform/common/Makefile"
cat > "$workspace/manifest.xml" <<'XML'
<manifest>
  <project name="android_kernel_common_oneplus_sm8650" path="kernel_platform/common" revision="086936b3387b4018805500fa4069d09637fdb89b"/>
  <project name="android_kernel_modules_and_devicetree_oneplus_sm8650" path="./" revision="21a5694f721d3826ac9e101e5d65919f2a8e739e"/>
</manifest>
XML
printf 'CONFIG_MODULES=y\nCONFIG_MODVERSIONS=y\n' > "$common_out/.config"
printf '0x00\tsymbol\tvmlinux\tEXPORT_SYMBOL\n' > "$common_out/Module.symvers"

if output_text=$(bash "$builder" 2>&1); then
  echo 'FAIL: accepted missing build arguments' >&2
  exit 1
fi
[[ "$output_text" == *'Usage:'* ]] || { printf 'FAIL: bad missing-args diagnostic: %s\n' "$output_text" >&2; exit 1; }
for helper in "$wifi_builder" "$nfc_builder" "$vhci_builder"; do
  if output_text=$(bash "$helper" 2>&1); then
    printf 'FAIL: %s accepted missing arguments\n' "$helper" >&2
    exit 1
  fi
  [[ "$output_text" == *'Usage:'* ]] || { printf 'FAIL: helper missing-args diagnostic: %s\n' "$output_text" >&2; exit 1; }
done

"$builder" --validate-only OP-ACE-5 "$workspace" "$common_out" "$output"

# Validate both pinned target maps with archive manifests (no .git required).
sed -i \
  -e 's/086936b3387b4018805500fa4069d09637fdb89b/7499247fd6e0669a062ec44cce948ec1e9d4c75e/' \
  -e 's/21a5694f721d3826ac9e101e5d65919f2a8e739e/d5323ede4f2059880c54818abfc1ac22d7e8bd5f/' \
  "$workspace/manifest.xml"
"$builder" --validate-only OP-ACE-5-6.1.118 "$workspace" "$common_out" "$output"
sed -i \
  -e 's/7499247fd6e0669a062ec44cce948ec1e9d4c75e/086936b3387b4018805500fa4069d09637fdb89b/' \
  -e 's/d5323ede4f2059880c54818abfc1ac22d7e8bd5f/21a5694f721d3826ac9e101e5d65919f2a8e739e/' \
  "$workspace/manifest.xml"

if output_text=$(bash "$builder" --validate-only OP-ACE-5 "$tmpdir/no-workspace" "$common_out" "$output" 2>&1); then
  echo 'FAIL: accepted missing source manifest' >&2
  exit 1
fi
[[ "$output_text" == *'manifest.xml'* ]] || { printf 'FAIL: missing manifest diagnostic: %s\n' "$output_text" >&2; exit 1; }

rm "$common_out/.config"
if output_text=$(bash "$builder" --validate-only OP-ACE-5 "$workspace" "$common_out" "$output" 2>&1); then
  echo 'FAIL: accepted missing .config' >&2
  exit 1
fi
[[ "$output_text" == *'.config'* ]] || { printf 'FAIL: missing .config diagnostic: %s\n' "$output_text" >&2; exit 1; }
printf 'CONFIG_MODULES=y\nCONFIG_MODVERSIONS=y\n' > "$common_out/.config"

rm "$common_out/Module.symvers"
if output_text=$(bash "$builder" --validate-only OP-ACE-5 "$workspace" "$common_out" "$output" 2>&1); then
  echo 'FAIL: accepted missing Module.symvers' >&2
  exit 1
fi
[[ "$output_text" == *'Module.symvers'* ]] || { printf 'FAIL: missing Module.symvers diagnostic: %s\n' "$output_text" >&2; exit 1; }
printf '0x00\tsymbol\tvmlinux\tEXPORT_SYMBOL\n' > "$common_out/Module.symvers"

sed -i 's/21a5694f721d3826ac9e101e5d65919f2a8e739e/deadbeef/' "$workspace/manifest.xml"
if output_text=$(bash "$builder" --validate-only OP-ACE-5 "$workspace" "$common_out" "$output" 2>&1); then
  echo 'FAIL: accepted wrong pinned modules revision' >&2
  exit 1
fi
[[ "$output_text" == *'revision mismatch'* ]] || { printf 'FAIL: wrong revision diagnostic: %s\n' "$output_text" >&2; exit 1; }
sed -i 's/deadbeef/21a5694f721d3826ac9e101e5d65919f2a8e739e/' "$workspace/manifest.xml"

# Source sync uses archives, so the fixture deliberately has no .git directory.
[[ ! -e "$workspace/.git" ]]

if output_text=$(bash "$builder" OP-ACE-5 "$workspace" "$common_out" "$output" 2>&1); then
  echo 'FAIL: normal build accepted config without VHCI module' >&2
  exit 1
fi
[[ "$output_text" == *'CONFIG_BT_HCIVHCI=m is required'* ]] || {
  printf 'FAIL: missing VHCI config diagnostic: %s\n' "$output_text" >&2
  exit 1
}

# An existing module artifact with the wrong architecture fails closed.
mkdir -p "$common_out/drivers/bluetooth"
printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\002\000\076\000' \
  > "$common_out/drivers/bluetooth/hci_vhci.ko"
if output_text=$(bash "$builder" --validate-only OP-ACE-5 "$workspace" "$common_out" "$output" 2>&1); then
  echo 'FAIL: accepted wrong-architecture hci_vhci.ko' >&2
  exit 1
fi
[[ "$output_text" == *'not AArch64'* ]] || { printf 'FAIL: wrong module architecture diagnostic: %s\n' "$output_text" >&2; exit 1; }
rm "$common_out/drivers/bluetooth/hci_vhci.ko"

# Existing package gate owns the no-components/no-script-only package contract.
echo 'NetHunter build contract tests passed'
