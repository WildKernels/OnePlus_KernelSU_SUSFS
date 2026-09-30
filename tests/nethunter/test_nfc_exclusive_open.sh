#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
patch="$root/patches/nfc/0001-exclusive-open.patch"
tmpdir=$(mktemp -d)
trap 'if [[ "${KEEP_NFC_FIXTURE:-0}" == 1 ]]; then printf "fixture=%s\\n" "$tmpdir"; else rm -rf "$tmpdir"; fi' EXIT

[[ -f "$patch" ]] || { echo 'FAIL: NFC exclusive-open patch missing' >&2; exit 1; }
fixture="$root/tests/nethunter/fixtures/nxp-nfc"
[[ -f "$fixture/common.c" && -f "$fixture/common.h" ]] || {
  echo 'FAIL: pinned NXP driver fixture missing' >&2; exit 1;
}
driver="$tmpdir/vendor/nxp/opensource/driver"
mkdir -p "$driver/nfc"
cp "$fixture/common.c" "$driver/nfc/common.c"
cp "$fixture/common.h" "$driver/nfc/common.h"

git -C "$tmpdir" init -q
git -C "$tmpdir" add vendor/nxp/opensource/driver/nfc/common.h vendor/nxp/opensource/driver/nfc/common.c
(cd "$tmpdir" && git apply --check "$patch")
(cd "$tmpdir" && git apply "$patch")

grep -q 'int nh_owner_tgid;' "$driver/nfc/common.h"
grep -q 'current->tgid' "$driver/nfc/common.c"
grep -q 'return -EBUSY;' "$driver/nfc/common.c"
grep -q 'nh_owner_tgid = 0;' "$driver/nfc/common.c"

# Placement guard: a zero-context patch applies at arbitrary offsets and can
# land the ownership checks outside nfc_dev_open/nfc_dev_close. Require each
# inserted line to sit inside the right function body.
python3 - "$driver/nfc/common.c" <<'PY'
import re
import sys

text = open(sys.argv[1]).read()
funcs = {}
for name in ("nfc_dev_open", "nfc_dev_close"):
    m = re.search(r"\nint %s\(struct inode \*inode, struct file \*filp\)\n\{" % name, text)
    if not m:
        raise SystemExit(f"FAIL: {name} not found after patch")
    start = m.end()
    end = text.index("\n}\n", start)
    funcs[name] = text[start:end]

if "nh_owner_tgid != current->tgid" not in funcs["nfc_dev_open"]:
    raise SystemExit("FAIL: owner check not inside nfc_dev_open (patch misplaced)")
if "nh_owner_tgid = current->tgid" not in funcs["nfc_dev_open"]:
    raise SystemExit("FAIL: owner assignment not inside nfc_dev_open (patch misplaced)")
if "nh_owner_tgid = 0" not in funcs["nfc_dev_close"]:
    raise SystemExit("FAIL: owner clear not inside nfc_dev_close (patch misplaced)")
if "int nh_set_nofreeze = 0;" not in funcs["nfc_dev_open"]:
    raise SystemExit("FAIL: nh_set_nofreeze declaration not inside nfc_dev_open")
PY
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
if output=$("$ADB" shell su -c "$tool probe" 2>&1); then
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
