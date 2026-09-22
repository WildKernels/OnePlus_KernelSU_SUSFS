#!/bin/bash
# Build hci_vhci.ko (CONFIG_BT_HCIVHCI=m) against the built kernel tree.
# The kernel builds drivers/bluetooth/hci_vhci.o — module name is hci_vhci.
# Usage: build_btvhci.sh <OP-ACE-5|OP-ACE-5-6.1.118>
set -euo pipefail

TARGET="${1:?Usage: $0 <OP-ACE-5|OP-ACE-5-6.1.118>}"
case "$TARGET" in
  OP-ACE-5|OP-ACE-5-6.1.118) ;;
  *) echo "ERROR: Unknown target: $TARGET" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KERNEL_SRC="${KERNEL_SRC:?Set KERNEL_SRC to the synced OnePlus kernel workspace root}"
COMMON_SRC="$KERNEL_SRC/kernel_platform/common"
OUT="${NH_OUT:-/tmp/nh-build/$TARGET}"
mkdir -p "$OUT"

# Common kernel must have a full build output (Module.symvers needed for CRCs)
[ -f "$COMMON_SRC/out/Module.symvers" ] || {
  echo "ERROR: $COMMON_SRC/out/Module.symvers not found" >&2
  echo "A full common kernel build is required before building modules" >&2
  exit 1
}

CLANG_DIR="$KERNEL_SRC/kernel_platform/prebuilts/clang/host/linux-x86/clang-r487747c/bin"
export PATH="$CLANG_DIR:$PATH"
export ARCH=arm64
export LLVM=1 LLVM_IAS=1
export CC="$CLANG_DIR/clang"
export LD=ld.lld

echo "=== NetHunter hci_vhci module build ==="
echo "Target: $TARGET"
echo "Common: $COMMON_SRC"
echo "Output: $OUT/hci_vhci.ko"

# Enable module in a copy of the built config, then build external module
cp "$COMMON_SRC/out/.config" "$COMMON_SRC/out/.config.nethunter-backup"
trap 'mv "$COMMON_SRC/out/.config.nethunter-backup" "$COMMON_SRC/out/.config" 2>/dev/null || true' EXIT

"$COMMON_SRC/scripts/config" --file "$COMMON_SRC/out/.config" -e BT -e BT_HCIVHCI -d BT_HCIVHCI_MODULE_DISABLED 2>/dev/null || \
  "$COMMON_SRC/scripts/config" --file "$COMMON_SRC/out/.config" -e BT -e BT_HCIVHCI

make -C "$COMMON_SRC" O=out olddefconfig
make -C "$COMMON_SRC" O=out M=drivers/bluetooth modules

KO="$COMMON_SRC/out/drivers/bluetooth/hci_vhci.ko"
[ -f "$KO" ] || { echo "ERROR: hci_vhci.ko not built at $KO" >&2; exit 1; }

cp "$KO" "$OUT/hci_vhci.ko"

echo ""
echo "Build complete: $OUT/hci_vhci.ko"
modinfo -F name "$OUT/hci_vhci.ko"
modinfo -F vermagic "$OUT/hci_vhci.ko"
modinfo -F depends "$OUT/hci_vhci.ko" || true
sha256sum "$OUT/hci_vhci.ko"
