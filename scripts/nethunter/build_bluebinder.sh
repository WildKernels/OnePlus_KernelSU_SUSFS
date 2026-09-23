#!/usr/bin/env bash
# Build and verify pinned Bluebinder for AArch64 Android.
set -euo pipefail

BLUEBINDER_COMMIT=c3e1b155e308f6df9c9a02dbd909a44e7319ab7d

usage() {
  echo "Usage: $0 [--verify-only <source_dir> <prebuilt_libs_dir> <binary>]" >&2
  echo "       $0 (requires ANDROID_NDK_HOME and NH_PREBUILT_LIBS)" >&2
  exit 2
}

verify_artifact() {
  local source_dir="$1" prebuilt_libs="$2" binary="$3" revision dynamic
  unset PKG_CONFIG_PATH
  export PKG_CONFIG_LIBDIR="$prebuilt_libs/lib/pkgconfig:$prebuilt_libs/share/pkgconfig"
  [[ -f "$source_dir/Makefile" && -f "$source_dir/bluebinder.c" ]] || {
    echo "ERROR: Bluebinder source is incomplete: $source_dir" >&2
    return 1
  }
  grep -Eq '^DEPEND_LIBS[[:space:]]*=.*libgbinder.*glib-2\.0' "$source_dir/Makefile" || {
    echo "ERROR: pinned Bluebinder Makefile dependency contract changed" >&2
    return 1
  }
  revision=$(git -C "$source_dir" rev-parse HEAD 2>/dev/null || true)
  [[ "$revision" == "$BLUEBINDER_COMMIT" ]] || {
    echo "ERROR: Bluebinder revision mismatch: got ${revision:-unknown}, expected $BLUEBINDER_COMMIT" >&2
    return 1
  }
  [[ -d "$prebuilt_libs/include" && -d "$prebuilt_libs/lib" ]] || {
    echo "ERROR: target dependency headers/libraries missing in $prebuilt_libs" >&2
    return 1
  }
  [[ -f "$prebuilt_libs/lib/pkgconfig/libgbinder.pc" && -f "$prebuilt_libs/lib/pkgconfig/glib-2.0.pc" ]] || {
    echo "ERROR: target libgbinder/glib-2.0 pkg-config metadata missing" >&2
    return 1
  }
  [[ -e "$prebuilt_libs/lib/libgbinder.so" && -e "$prebuilt_libs/lib/libglib-2.0.so" ]] || {
    echo "ERROR: target libgbinder/glib-2.0 shared libraries missing" >&2
    return 1
  }
  pkg-config --exists libgbinder glib-2.0 || {
    echo "ERROR: target pkg-config cannot resolve libgbinder and glib-2.0" >&2
    return 1
  }
  [[ -s "$binary" ]] || { echo "ERROR: Bluebinder binary missing: $binary" >&2; return 1; }
  file "$binary" | grep -q 'ELF 64-bit.*ARM aarch64' || {
    echo "ERROR: Bluebinder binary is not AArch64: $binary" >&2
    return 1
  }
  command -v readelf >/dev/null 2>&1 || { echo "ERROR: readelf required" >&2; return 1; }
  dynamic=$(readelf -d "$binary" 2>/dev/null) || {
    echo "ERROR: cannot inspect Bluebinder dynamic dependencies" >&2
    return 1
  }
  [[ "$dynamic" == *'libgbinder.so'* && "$dynamic" == *'libglib-2.0.so'* ]] || {
    echo "ERROR: Bluebinder lacks libgbinder/glib-2.0 dynamic dependencies" >&2
    return 1
  }
  if printf '%s\n' "$dynamic" | grep -E 'RPATH|RUNPATH|/usr/lib|/usr/local|/home/[^/]+' >/dev/null; then
    echo "ERROR: Bluebinder contains host-only runtime paths" >&2
    return 1
  fi
  local needed
  while IFS= read -r needed; do
    case "$needed" in
      libc.so|libm.so|libdl.so|liblog.so|libandroid.so|libc++_shared.so) ;;
      *) [[ -e "$(dirname "$binary")/lib64/$needed" ]] || {
        echo "ERROR: bundled Android runtime library missing: $needed" >&2
        return 1
      } ;;
    esac
  done < <(readelf -d "$binary" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')
  local lib lib_dynamic libdir
  libdir="$(dirname "$binary")/lib64"
  for lib in "$libdir"/*.so*; do
    [[ -e "$lib" ]] || continue
    file "$lib" | grep -q 'ELF 64-bit.*ARM aarch64' || {
      echo "ERROR: bundled runtime library is not AArch64: $lib" >&2
      return 1
    }
    lib_dynamic=$(readelf -d "$lib" 2>/dev/null) || {
      echo "ERROR: cannot inspect bundled runtime library: $lib" >&2
      return 1
    }
    if printf '%s\n' "$lib_dynamic" | grep -E 'RPATH|RUNPATH|/usr/lib|/usr/local|/home/[^/]+' >/dev/null; then
      echo "ERROR: bundled runtime library contains host-only paths: $lib" >&2
      return 1
    fi
  done
  printf 'Bluebinder artifact valid: commit=%s sha256=%s\n' \
    "$revision" "$(sha256sum "$binary" | cut -d' ' -f1)"
}

if [[ "${1:-}" == --verify-only ]]; then
  [[ $# -eq 4 ]] || usage
  shift
  verify_artifact "$1" "$2" "$3"
  exit $?
fi
[[ $# -eq 0 ]] || usage

OUT="${NH_OUT:-/tmp/nh-build/bluebinder}"
SRC="$OUT/src-$BLUEBINDER_COMMIT"
mkdir -p "$OUT"

if [[ ! -d "$SRC/.git" ]]; then
  git clone --no-checkout --filter=blob:none \
    https://github.com/mer-hybris/bluebinder.git "$SRC"
fi
git -C "$SRC" fetch --depth 1 origin "$BLUEBINDER_COMMIT"
git -C "$SRC" checkout --detach "$BLUEBINDER_COMMIT"
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$BLUEBINDER_COMMIT" ]] || {
  echo "ERROR: failed to checkout pinned Bluebinder commit" >&2
  exit 1
}

NDK_ROOT="${ANDROID_NDK_HOME:-${NDK_HOME:-}}"
[[ -n "$NDK_ROOT" ]] || { echo "ERROR: Set ANDROID_NDK_HOME or NDK_HOME to Android NDK path" >&2; exit 1; }
TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"
CC="$TOOLCHAIN/bin/aarch64-linux-android34-clang"
[[ -x "$CC" ]] || { echo "ERROR: Android NDK Clang missing: $CC" >&2; exit 1; }

PREBUILT_LIBS="${NH_PREBUILT_LIBS:-$OUT/prebuilt}"
[[ -f "$PREBUILT_LIBS/lib/pkgconfig/libgbinder.pc" && -f "$PREBUILT_LIBS/lib/pkgconfig/glib-2.0.pc" ]] || {
  echo "ERROR: Set NH_PREBUILT_LIBS to AArch64 Android libgbinder and GLib headers/libraries/pkg-config files" >&2
  exit 1
}

# Prevent host pkg-config metadata from contaminating Android compile/link flags.
unset PKG_CONFIG_PATH
export PKG_CONFIG_LIBDIR="$PREBUILT_LIBS/lib/pkgconfig:$PREBUILT_LIBS/share/pkgconfig"
export CC
export CFLAGS="--sysroot=$TOOLCHAIN/sysroot -I$PREBUILT_LIBS/include"
export LDFLAGS="-L$PREBUILT_LIBS/lib"

pkg-config --exists libgbinder glib-2.0 || {
  echo "ERROR: target pkg-config failed for libgbinder and glib-2.0" >&2
  exit 1
}

rm -f "$SRC/bluebinder"
make -C "$SRC" CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" USE_SYSTEMD=0

mkdir -p "$OUT"
cp "$SRC/bluebinder" "$OUT/bluebinder"
rm -rf "$OUT/lib64"
mkdir -p "$OUT/lib64"
shopt -s nullglob
runtime_libs=("$PREBUILT_LIBS"/lib/*.so*)
shopt -u nullglob
[[ ${#runtime_libs[@]} -gt 0 ]] || { echo "ERROR: no target shared libraries to bundle from $PREBUILT_LIBS/lib" >&2; exit 1; }
cp -a "${runtime_libs[@]}" "$OUT/lib64/"
PKG_CONFIG_LIBDIR="$PREBUILT_LIBS/lib/pkgconfig:$PREBUILT_LIBS/share/pkgconfig" \
  verify_artifact "$SRC" "$PREBUILT_LIBS" "$OUT/bluebinder"

jq -n \
  --arg commit "$BLUEBINDER_COMMIT" \
  --arg sha256 "$(sha256sum "$OUT/bluebinder" | cut -d' ' -f1)" \
  --arg signer "$(git -C "$SRC" log -1 --format=%an)" \
  --arg dependencies "libgbinder,glib-2.0" \
  --arg libdir_sha256 "$(find "$OUT/lib64" -type f -name '*.so*' -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)" \
  '{commit:$commit,sha256:$sha256,source_author:$signer,dependencies:$dependencies,libdir_sha256:$libdir_sha256,architecture:"aarch64-android"}' \
  > "$OUT/bluebinder-evidence.json"

echo "Build complete: $OUT/bluebinder"
