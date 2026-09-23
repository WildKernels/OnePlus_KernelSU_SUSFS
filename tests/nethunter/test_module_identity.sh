#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
customize="$root/nethunter/module/customize.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
moddir="$tmpdir/module"
mkdir -p "$moddir"

cat > "$moddir/module.prop" <<'PROP'
target=OP-ACE-5
device=pineapple
model=ONEPLUS PKG110
build_fingerprint=oneplus/PKG110/PKG110:16/TEST/release-keys
kernel_release=6.1.174-g638ecc425319
kernel_vermagic=6.1.174-g638ecc425319
PROP

run_customize() {
  env MODPATH="$moddir" NH_STATE_DIR="$tmpdir/state" CUSTOMIZE="$customize" \
    bash -c '
      grep_prop() { grep "^$1=" "$2" | cut -d= -f2-; }
      ui_print() { :; }
      abort() { printf "%s\n" "$*" >&2; exit 1; }
      mkdir() { :; }
      chmod() { :; }
      getprop() {
        case "$1" in
          ro.product.model) printf "%s\n" "${TEST_MODEL:-ONEPLUS PKG110}" ;;
          ro.product.device) printf "%s\n" "${TEST_DEVICE:-pineapple}" ;;
          ro.build.fingerprint) printf "%s\n" "${TEST_FINGERPRINT:-oneplus/PKG110/PKG110:16/TEST/release-keys}" ;;
          *) return 1 ;;
        esac
      }
      uname() { printf "%s\n" "${TEST_KERNEL:-6.1.174-g638ecc425319}"; }
      source "$CUSTOMIZE"
    '
}

if output=$(run_customize 2>&1); then
  :
else
  printf 'FAIL: rejected matching device identity: %s\n' "$output" >&2
  exit 1
fi

if output=$(TEST_MODEL=WRONG run_customize 2>&1); then
  echo 'FAIL: installer accepted wrong device model' >&2
  exit 1
fi
[[ "$output" == *'model mismatch'* ]] || {
  printf 'FAIL: model mismatch reason missing: %s\n' "$output" >&2
  exit 1
}

if output=$(TEST_DEVICE=wrong run_customize 2>&1); then
  echo 'FAIL: installer accepted wrong device codename' >&2
  exit 1
fi
[[ "$output" == *'device mismatch'* ]] || {
  printf 'FAIL: device mismatch reason missing: %s\n' "$output" >&2
  exit 1
}

if output=$(TEST_FINGERPRINT=wrong run_customize 2>&1); then
  echo 'FAIL: installer accepted wrong build fingerprint' >&2
  exit 1
fi
[[ "$output" == *'fingerprint mismatch'* ]] || {
  printf 'FAIL: fingerprint mismatch reason missing: %s\n' "$output" >&2
  exit 1
}

if output=$(TEST_KERNEL=wrong run_customize 2>&1); then
  echo 'FAIL: installer accepted wrong kernel release' >&2
  exit 1
fi
[[ "$output" == *'kernel release mismatch'* ]] || {
  printf 'FAIL: kernel mismatch reason missing: %s\n' "$output" >&2
  exit 1
}

echo 'NetHunter module identity tests passed'
