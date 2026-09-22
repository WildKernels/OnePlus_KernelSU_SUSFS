#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
pack="$root/scripts/nethunter/pack_takeover_zip.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0
pass() { pass=$((pass + 1)); echo "  PASS: $1"; }
fail() { fail=$((fail + 1)); echo "  FAIL: $1"; }

# --- Build fake artifacts: wifi ko is x86 ELF (wrong arch) ---
build_dir="$tmpdir/build"
mkdir -p "$build_dir"
printf '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00' > "$build_dir/qca_cld3_kiwi_v2.ko"
printf '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00' > "$build_dir/hci_vhci.ko"

target="$tmpdir/target"
mkdir -p "$target"
cp -r "$root/nethunter" "$target/nethunter"
cp -r "$root/scripts" "$target/scripts"
mkdir -p "$target/dist"

if output=$(cd "$target" && NH_BUILD_DIR="$build_dir" bash scripts/nethunter/pack_takeover_zip.sh OP-ACE-5 test 2>&1); then
  fail "pack succeeded with wrong-arch bt module"
else
  if grep -q 'qca_cld3_kiwi_v2.ko is not AArch64' <<< "$output"; then
    pass "wrong-arch module rejected with clear error"
  else
    fail "wrong-arch module rejected but error unclear: $output"
  fi
fi

# --- All components missing must fail ---
build_empty="$tmpdir/empty"
mkdir -p "$build_empty"
rm -f "$target/nethunter/nfc/nci_raw_tool"
if output=$(cd "$target" && NH_BUILD_DIR="$build_empty" bash scripts/nethunter/pack_takeover_zip.sh OP-ACE-5 test 2>&1); then
  fail "pack succeeded with no built components"
else
  if grep -q 'no takeover components were built' <<< "$output"; then
    pass "empty build rejected"
  else
    fail "empty build rejected but error unclear: $output"
  fi
fi

# --- Unknown target must fail ---
if output=$(cd "$target" && NH_BUILD_DIR="$build_dir" bash scripts/nethunter/pack_takeover_zip.sh OP-FAKE test 2>&1); then
  fail "pack accepted unknown target"
else
  if grep -q 'Unknown target' <<< "$output"; then
    pass "unknown target rejected"
  else
    fail "unknown target rejected but error unclear: $output"
  fi
fi

# --- Wrong-arch nci_raw_tool must be rejected ---
mkdir -p "$build_dir/usb"
touch "$build_dir/usb/placeholder"
cp nethunter/nfc/nci_raw_tool "$target/nethunter/nfc/nci_raw_tool"
if output=$(cd "$target" && NH_BUILD_DIR="$build_empty" bash scripts/nethunter/pack_takeover_zip.sh OP-ACE-5 test 2>&1); then
  fail "pack accepted x86 nci_raw_tool"
else
  if grep -q 'nci_raw_tool is not AArch64' <<< "$output"; then
    pass "x86 nci_raw_tool rejected"
  else
    fail "x86 nci_raw_tool rejected but error unclear: $output"
  fi
fi
rm -f "$target/nethunter/nfc/nci_raw_tool"

# --- Valid components produce a ZIP with matching module.prop hashes ---
mkdir -p "$build_dir/usb"
touch "$build_dir/usb/placeholder"
rm -f "$build_dir/qca_cld3_kiwi_v2.ko" "$build_dir/hci_vhci.ko"
# nci_raw_tool currently built for host x86; the pack gate must reject it
rm -f "$target/nethunter/nfc/nci_raw_tool"
if output=$(cd "$target" && NH_BUILD_DIR="$build_dir" NH_BLUEBINDER_BIN="$build_dir/bluebinder" bash scripts/nethunter/pack_takeover_zip.sh OP-ACE-5 test 2>&1); then
  fail "pack succeeded with no kernel modules at all"
  exit 1
else
  pass "pack requires at least one kernel module"
fi

# wifi ko valid AArch64 ELF placeholder: file magic check passes only on ELF 64-bit aarch64.
# Simulate by copying a real aarch64 ELF if available on the host; otherwise skip this branch.
skip_valid_zip=1
if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
  printf 'int main(void){return 0;}\n' > "$build_dir/main.c"
  if aarch64-linux-gnu-gcc -static -o "$build_dir/qca_cld3_kiwi_v2.ko" "$build_dir/main.c" 2>/dev/null; then
    skip_valid_zip=0
  fi
fi
if [[ "$skip_valid_zip" -eq 0 ]]; then
  if output=$(cd "$target" && NH_BUILD_DIR="$build_dir" NH_BLUEBINDER_BIN="$build_dir/bluebinder" bash scripts/nethunter/pack_takeover_zip.sh OP-ACE-5 test 2>&1); then
    zip_path=$(grep -o 'Created: .*' <<< "$output" | cut -d' ' -f2)
    if [[ -f "$zip_path" ]]; then
      prop=$(unzip -p "$zip_path" module.prop)
      sha_wifi=$(sha256sum "$build_dir/qca_cld3_kiwi_v2.ko" | cut -d' ' -f1)
      if grep -q "sha256_wifi=$sha_wifi" <<< "$prop"; then
        pass "module.prop carries real wifi sha256"
      else
        fail "module.prop missing real wifi sha256"
      fi
      if unzip -l "$zip_path" | grep -q 'vendor_dlkm_override/qca_cld3_kiwi_v2.ko'; then
        pass "wifi module present in ZIP"
      else
        fail "wifi module missing from ZIP"
      fi
    else
      fail "ZIP not created: $output"
    fi
  else
    fail "valid pack failed: $output"
  fi
else
  echo "  SKIP: valid-ZIP branch (no aarch64 cross-compiler on host)"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
echo "PACK GATE TESTS PASSED"
