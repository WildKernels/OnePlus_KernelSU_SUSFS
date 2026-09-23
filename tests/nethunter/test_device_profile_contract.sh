#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
validator="$root/scripts/nethunter/validate_device_profile.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/valid.json" <<'JSON'
{
  "schema_version": 2,
  "created_at": "2026-09-23T00:00:00Z",
  "device": {
    "model": "ONEPLUS PKG110",
    "codename": "pineapple",
    "build_fingerprint": "oneplus/PKG110/PKG110:16/TEST/release-keys"
  },
  "kernel": {"release": "6.1.174-g638ecc425319", "architecture": "aarch64"},
  "nethunter": {"rootfs": "present"},
  "modules": {
    "wifi": {"path": "/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko", "sha256": "abc123", "modinfo": "", "loaded": "", "con_mode": "0", "interfaces": "", "phys": "", "availability": "available"},
    "bluetooth": {"vhci_name": "hci_vhci.ko", "device_node": "", "rfkill": "", "manager": "", "services": "", "availability": "available"},
    "nfc": {"path": "/vendor_dlkm/lib/modules/nxp-nci.ko", "driver": "", "node": "", "state": "", "properties": "", "hal_service": "", "availability": "available"}
  },
  "usb": {"config": "mtp,adb", "roles": "", "gadgets": "", "udcs": "", "functions": "", "availability": "available"},
  "gnss": {"service": "android.hardware.gnss.IGnss/default", "location_dump": "", "availability": "available"}
}
JSON

"$validator" "$tmpdir/valid.json"
jq empty "$root/docs/nethunter/device-profile.schema.json"
"$validator" "$root/docs/nethunter/device-profile.example.json"

jq '.kernel.architecture = "x86_64"' "$tmpdir/valid.json" > "$tmpdir/wrong-arch.json"
if output=$("$validator" "$tmpdir/wrong-arch.json" 2>&1); then
  echo 'FAIL: accepted non-AArch64 profile' >&2
  exit 1
fi
[[ "$output" == *'kernel.architecture'* ]] || {
  printf 'FAIL: wrong architecture diagnostic lacks JSON path: %s\n' "$output" >&2
  exit 1
}

jq 'del(.kernel.release)' "$tmpdir/valid.json" > "$tmpdir/missing-release.json"
if output=$("$validator" "$tmpdir/missing-release.json" 2>&1); then
  echo 'FAIL: accepted profile with missing kernel release' >&2
  exit 1
fi
[[ "$output" == *'kernel.release'* ]] || {
  printf 'FAIL: missing release diagnostic lacks JSON path: %s\n' "$output" >&2
  exit 1
}

printf '{"schema_version": 2,\n' > "$tmpdir/malformed.json"
if "$validator" "$tmpdir/malformed.json" >/dev/null 2>&1; then
  echo 'FAIL: accepted malformed JSON' >&2
  exit 1
fi

echo 'Device profile contract tests passed'
