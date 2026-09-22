#!/bin/bash
# Build qca_cld3_kiwi_v2.ko for NetHunter from pinned OnePlus source.
#
# The Wi-Fi injection patch does not exist yet: upstream references
# (Loukious 25875eb, brokestar233 be87f12) target different kernel trees and
# must be ported and compile-tested against this tree before use. This script
# builds the UNMODIFIED module so the restore cycle (Phase A) can be proven
# on-device first.
#
# Usage: build_stock_wifi.sh <OP-ACE-5|OP-ACE-5-6.1.118>
set -euo pipefail

TARGET="${1:?Usage: $0 <OP-ACE-5|OP-ACE-5-6.1.118>}"
case "$TARGET" in
  OP-ACE-5)       MOD_REV="21a5694f721d3826ac9e101e5d65919f2a8e739e" ;;
  OP-ACE-5-6.1.118) MOD_REV="d5323ede4f2059880c54818abfc1ac22d7e8bd5f" ;;
  *) echo "ERROR: Unknown target: $TARGET" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KERNEL_SRC="${KERNEL_SRC:?Set KERNEL_SRC to the synced OnePlus kernel workspace root}"
WLAN_DIR="$KERNEL_SRC/vendor/qcom/opensource/wlan"
OUT="${NH_OUT:-/tmp/nh-build/$TARGET}"
mkdir -p "$OUT"

echo "=== NetHunter stock Wi-Fi module build ==="
echo "Target:    $TARGET"
echo "Source:    $KERNEL_SRC (modules tree must be at $MOD_REV)"
echo "Output:    $OUT/qca_cld3_kiwi_v2.ko"
echo ""

# Verify the modules tree matches the pinned revision
actual_rev=$(git -C "$WLAN_DIR/../.." rev-parse HEAD 2>/dev/null || true)
if [ -n "$actual_rev" ] && [ "$actual_rev" != "$MOD_REV" ]; then
  echo "ERROR: modules tree is at $actual_rev, expected $MOD_REV" >&2
  exit 1
fi

# msm-kernel out dir must exist with a full build (Module.symvers required
# for CONFIG_MODVERSIONS CRC checks; modules_prepare alone is not enough)
MSM_OUT=$(find "$KERNEL_SRC/kernel_platform" -maxdepth 4 -name Module.symvers -path '*msm-kernel*' 2>/dev/null | head -1)
[ -n "$MSM_OUT" ] || {
  echo "ERROR: msm-kernel Module.symvers not found under $KERNEL_SRC/kernel_platform" >&2
  echo "A full msm-kernel build (not modules_prepare) is required for MODVERSIONS CRCs" >&2
  exit 1
}
MSM_OUT_DIR=$(dirname "$MSM_OUT")
echo "Kernel out: $MSM_OUT_DIR"

CLANG_DIR="$KERNEL_SRC/kernel_platform/prebuilts/clang/host/linux-x86/clang-r487747c/bin"
export PATH="$CLANG_DIR:$PATH"
export ARCH=arm64
export LLVM=1 LLVM_IAS=1

# Build through the Makefile wrapper (uses KERNEL_SRC + M per qcacld-3.0 convention)
make -C "$WLAN_DIR/qcacld-3.0" \
  KERNEL_SRC="$MSM_OUT_DIR" \
  M="$WLAN_DIR/qcacld-3.0" \
  WLAN_ROOT="$WLAN_DIR/qcacld-3.0" \
  MODNAME=qca_cld3_kiwi_v2 \
  CONFIG_QCA_CLD_WLAN=m \
  KBUILD_EXTRA="CONFIG_CNSS_KIWI_V2=y CONFIG_QCA_WIFI_KIWI=y CONFIG_KIWI_HEADERS_DEF=y" \
  O="$MSM_OUT_DIR" \
  modules

KO=$(find "$WLAN_DIR/qcacld-3.0" -name 'qca_cld3_kiwi_v2.ko' -newer "$MSM_OUT_DIR/Module.symvers" 2>/dev/null | head -1)
[ -n "$KO" ] || KO=$(find "$WLAN_DIR/qcacld-3.0" -name 'qca_cld3_kiwi_v2.ko' -type f | head -1)
[ -n "$KO" ] || { echo "ERROR: built module not found" >&2; exit 1; }

cp "$KO" "$OUT/qca_cld3_kiwi_v2.ko"

echo ""
echo "Build complete: $OUT/qca_cld3_kiwi_v2.ko"
modinfo -F vermagic "$OUT/qca_cld3_kiwi_v2.ko" || true
modinfo -F depends "$OUT/qca_cld3_kiwi_v2.ko" || true
sha256sum "$OUT/qca_cld3_kiwi_v2.ko"
