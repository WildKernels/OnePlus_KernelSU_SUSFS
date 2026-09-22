#!/bin/bash
set -euo pipefail

TARGET="${1:?Usage: $0 <OP-ACE-5|OP-ACE-5-6.1.118>}"
VERSION="${2:?Version string required}"

case "$TARGET" in
  OP-ACE-5|OP-ACE-5-6.1.118) ;;
  *) echo "ERROR: Unknown target: $TARGET" >&2; exit 1 ;;
esac

BUILD_DIR="${NH_BUILD_DIR:-/tmp/nh-build/$TARGET}"
OUT_DIR="dist"
mkdir -p "$OUT_DIR"

PACK_DIR="/tmp/nh-pack-$TARGET"
rm -rf "$PACK_DIR"
mkdir -p "$PACK_DIR"/{system/bin,vendor_dlkm_override,META-INF/com/google/android}

# Copy framework + radio scripts
cp -r nethunter/framework "$PACK_DIR/"
cp -r nethunter/wifi "$PACK_DIR/"
cp -r nethunter/bt "$PACK_DIR/"
cp -r nethunter/nfc "$PACK_DIR/"

# Copy built binaries; every included component is verified
BUILT_COMPONENTS=""
if [ -f "$BUILD_DIR/qca_cld3_kiwi_v2.ko" ]; then
  if ! file "$BUILD_DIR/qca_cld3_kiwi_v2.ko" | grep -q 'ELF 64-bit.*ARM aarch64'; then
    echo "ERROR: qca_cld3_kiwi_v2.ko is not AArch64; refusing to package" >&2
    exit 1
  fi
  cp "$BUILD_DIR/qca_cld3_kiwi_v2.ko" "$PACK_DIR/vendor_dlkm_override/"
  BUILT_COMPONENTS="${BUILT_COMPONENTS}wifi,"
fi
if [ -f "$BUILD_DIR/hci_vhci.ko" ]; then
  if ! file "$BUILD_DIR/hci_vhci.ko" | grep -q 'ELF 64-bit.*ARM aarch64'; then
    echo "ERROR: hci_vhci.ko is not AArch64; refusing to package" >&2
    exit 1
  fi
  cp "$BUILD_DIR/hci_vhci.ko" "$PACK_DIR/vendor_dlkm_override/"
  BUILT_COMPONENTS="${BUILT_COMPONENTS}bt,"
fi
bluebinder_bin="${NH_BLUEBINDER_BIN:-/tmp/nh-build/bluebinder/bluebinder}"
if [ -f "$bluebinder_bin" ]; then
  if ! file "$bluebinder_bin" | grep -q 'ARM aarch64'; then
    echo "ERROR: bluebinder is not AArch64; refusing to package" >&2
    exit 1
  fi
  cp "$bluebinder_bin" "$PACK_DIR/system/bin/"
  BUILT_COMPONENTS="${BUILT_COMPONENTS}bluebinder,"
fi
if [ -f nethunter/nfc/nci_raw_tool ]; then
  if ! file nethunter/nfc/nci_raw_tool | grep -q 'ARM aarch64'; then
    echo "ERROR: nci_raw_tool is not AArch64; refusing to package" >&2
    exit 1
  fi
  cp nethunter/nfc/nci_raw_tool "$PACK_DIR/system/bin/"
  BUILT_COMPONENTS="${BUILT_COMPONENTS}nfc,"
fi

if [ -z "$BUILT_COMPONENTS" ]; then
  echo "ERROR: no takeover components were built; refusing to create a scripts-only ZIP" >&2
  exit 1
fi
echo "Built components: ${BUILT_COMPONENTS%,}"

# Generate module.prop with real hashes for included components only
SHA_QCA="not_built"
SHA_BTVHCI="not_built"
VERMAGIC="unknown"
SCMVERSION="unknown"
if [ -f "$PACK_DIR/vendor_dlkm_override/qca_cld3_kiwi_v2.ko" ]; then
  SHA_QCA=$(sha256sum "$PACK_DIR/vendor_dlkm_override/qca_cld3_kiwi_v2.ko" | cut -d' ' -f1)
  VERMAGIC=$(modinfo -F vermagic "$PACK_DIR/vendor_dlkm_override/qca_cld3_kiwi_v2.ko" 2>/dev/null || echo "unknown")
  SCMVERSION=$(modinfo -F scmversion "$PACK_DIR/vendor_dlkm_override/qca_cld3_kiwi_v2.ko" 2>/dev/null || echo "unknown")
fi
if [ -f "$PACK_DIR/vendor_dlkm_override/hci_vhci.ko" ]; then
  SHA_BTVHCI=$(sha256sum "$PACK_DIR/vendor_dlkm_override/hci_vhci.ko" | cut -d' ' -f1)
fi

sed -e "s/@@TARGET@@/$TARGET/g" \
    -e "s/@@VERSION@@/$VERSION/g" \
    -e "s/@@VERSION_CODE@@/1/g" \
    -e "s/@@VERMAGIC@@/$VERMAGIC/g" \
    -e "s/@@SCMVERSION@@/$SCMVERSION/g" \
    -e "s/@@SHA_QCA@@/$SHA_QCA/g" \
    -e "s/@@SHA_BTVHCI@@/$SHA_BTVHCI/g" \
    nethunter/module/module.prop.template > "$PACK_DIR/module.prop"

# Copy ReSukiSU install scripts
cp nethunter/module/customize.sh "$PACK_DIR/"
cp nethunter/module/post-fs-data.sh "$PACK_DIR/"
cp nethunter/module/service.sh "$PACK_DIR/"

# Create ZIP
ZIP_NAME="$OUT_DIR/nethunter-takeover-${TARGET}-${VERSION}.zip"
rm -f "$ZIP_NAME"
cd "$PACK_DIR"
zip -qr "$OLDPWD/$ZIP_NAME" .
cd "$OLDPWD"

echo "Created: $ZIP_NAME"
sha256sum "$ZIP_NAME"
