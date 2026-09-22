#!/bin/bash
# Cross-compile nci_raw_tool for aarch64 Android (Kali chroot compatible).
set -euo pipefail

NDK_ROOT="${ANDROID_NDK_HOME:-${NDK_HOME:-}}"
if [ -z "$NDK_ROOT" ]; then
  for candidate in /usr/local/lib/android/sdk/ndk-bundle "$GITHUB_WORKSPACE/ndk"; do
    [ -d "$candidate/toolchains/llvm/prebuilt/linux-x86_64/bin" ] && NDK_ROOT="$candidate" && break
  done
fi

CC="gcc"
if [ -n "$NDK_ROOT" ] && [ -x "$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android34-clang" ]; then
  CC="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android34-clang"
else
  # CI fallback: aarch64 cross gcc produces static aarch64 ELF that runs in
  # the Kali chroot only if glibc-compatible; NDK is preferred for Android.
  echo "WARNING: Android NDK not found; falling back to aarch64-linux-gnu-gcc" >&2
  CC="aarch64-linux-gnu-gcc"
fi

echo "CC: $CC"
make -C nethunter/nfc clean || true
make -C nethunter/nfc CC="$CC" CFLAGS="-Wall -O2 -static"

file nethunter/nfc/nci_raw_tool | grep -q 'ARM aarch64' || {
  echo "ERROR: nci_raw_tool is not AArch64 after build" >&2
  exit 1
}
sha256sum nethunter/nfc/nci_raw_tool
