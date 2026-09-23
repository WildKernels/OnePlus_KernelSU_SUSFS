#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
patch="$root/patches/nfc/0001-exclusive-open.patch"
tmpdir=$(mktemp -d)
trap 'if [[ "${KEEP_NFC_FIXTURE:-0}" == 1 ]]; then printf "fixture=%s\\n" "$tmpdir"; else rm -rf "$tmpdir"; fi' EXIT

[[ -f "$patch" ]] || { echo 'FAIL: NFC exclusive-open patch missing' >&2; exit 1; }
driver="$tmpdir/vendor/nxp/opensource/driver"
mkdir -p "$driver/nfc"

python3 - "$driver" <<'PY'
from pathlib import Path
import sys

driver = Path(sys.argv[1])
header = ["/* pinned-source fixture */"] * 270
header[261] = "\tstruct mutex dev_ref_mutex;"   # line 262
header[262] = "\tunsigned int dev_ref_count;"  # line 263
header[263] = "\tstruct class *nfc_class;"    # line 264
(driver / "nfc/common.h").write_text("\n".join(header) + "\n")

source = ["/* pinned-source fixture */"] * 890
source[772] = "int nfc_dev_open(struct inode *inode, struct file *filp)"  # 773
source[773] = "{"  # 774
source[774] = "\tstruct nfc_dev *nfc_dev = NULL;"  # 775
source[775] = ""  # 776
source[776] = "\tnfc_dev = container_of(inode->i_cdev, struct nfc_dev, c_dev);"  # 777
source[777] = ""  # 778
source[787] = "\tif (!(current->flags & PF_NOFREEZE)) {"  # 788
source[788] = "\t\tcurrent->flags |= PF_NOFREEZE;"  # 789
source[789] = "\t\tpr_debug(\"NxpDrv: %s: current->flags 0x%x. \\n\", __func__, current->flags);"  # 790
source[790] = "\t}"  # 791
source[792] = "\tmutex_lock(&nfc_dev->dev_ref_mutex);"  # 793
source[793] = ""  # 794
source[794] = "\tfilp->private_data = nfc_dev;"  # 795
source[851] = "\tif (nfc_dev->dev_ref_count > 0)"  # 852
source[852] = "\t\tnfc_dev->dev_ref_count = nfc_dev->dev_ref_count - 1;"  # 853
source[853] = ""  # 854
source[854] = "\tfilp->private_data = NULL;"  # 855
(driver / "nfc/common.c").write_text("\n".join(source) + "\n")
PY

git -C "$tmpdir" init -q
git -C "$tmpdir" add vendor/nxp/opensource/driver/nfc/common.h vendor/nxp/opensource/driver/nfc/common.c
(cd "$tmpdir" && git apply --check "$patch")
(cd "$tmpdir" && git apply "$patch")

grep -q 'int nh_owner_tgid;' "$driver/nfc/common.h"
grep -q 'current->tgid' "$driver/nfc/common.c"
grep -q 'return -EBUSY;' "$driver/nfc/common.c"
grep -q 'nh_owner_tgid = 0;' "$driver/nfc/common.c"
echo 'NFC exclusive-open patch fixture passed'

if [[ "${NH_RUN_DEVICE_TEST:-0}" != 1 ]]; then
  echo 'SKIP: exact-device two-owner test (set NH_RUN_DEVICE_TEST=1 on target-connected host)'
  exit 0
fi

ADB="${ADB:-adb}"
MODULE_DIR="${NH_MODULE_DIR:-/data/adb/modules/nethunter_takeover_OP-ACE-5}"
"$ADB" get-state 2>/dev/null | grep -qx device || {
  echo 'ERROR: exact-device test requested but ADB device is unavailable' >&2
  exit 1
}

acquire="$MODULE_DIR/nfc/nh-nfc-acquire.sh"
release="$MODULE_DIR/nfc/nh-nfc-release.sh"
tool="$MODULE_DIR/system/bin/nci_raw_tool"
acquired=0
cleanup() {
  if [[ "$acquired" == 1 ]]; then
    "$ADB" shell su -c "$release" >/dev/null 2>&1 || true
  fi
}
trap 'cleanup; rm -rf "$tmpdir"' EXIT

"$ADB" shell su -c "$acquire"
acquired=1
if output=$("$ADB" shell su -c "$tool check-open" 2>&1); then
  echo 'FAIL: second process opened /dev/nq-nci while NetHunter session owns it' >&2
  exit 1
fi
[[ "$output" == *'Device or resource busy'* ]] || {
  printf 'FAIL: second open did not fail with EBUSY: %s\n' "$output" >&2
  exit 1
}

"$ADB" shell su -c "$release"
acquired=0
"$ADB" shell su -c 'dumpsys nfc' | grep -q 'mState=on'
echo 'NFC exact-device exclusivity and restore passed'
