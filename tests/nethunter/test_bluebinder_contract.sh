#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
builder="$root/scripts/nethunter/build_bluebinder.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

[[ -x "$builder" ]] || { echo 'FAIL: build_bluebinder.sh is missing' >&2; exit 1; }

src="$tmpdir/source"
prebuilt="$tmpdir/prebuilt"
binary="$tmpdir/bluebinder"
mockbin="$tmpdir/bin"
mkdir -p "$src/.git" "$prebuilt/include" "$prebuilt/lib/pkgconfig" "$prebuilt/lib" "$mockbin"
cat > "$src/Makefile" <<'MAKE'
DEPEND_LIBS = libgbinder glib-2.0
MAKE
touch "$src/bluebinder.c"
touch "$prebuilt/lib/pkgconfig/libgbinder.pc" "$prebuilt/lib/pkgconfig/glib-2.0.pc"
touch "$prebuilt/lib/libgbinder.so" "$prebuilt/lib/libglib-2.0.so"
mkdir -p "$tmpdir/lib64"
cp "$prebuilt/lib/libgbinder.so" "$prebuilt/lib/libglib-2.0.so" "$tmpdir/lib64/"
printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\003\000\267\000' > "$binary"

cat > "$mockbin/git" <<'GIT'
#!/usr/bin/env bash
if [[ "$1" == -C && "$3" == rev-parse && "$4" == HEAD ]]; then
  printf '%s\n' "${MOCK_GIT_REV:-c3e1b155e308f6df9c9a02dbd909a44e7319ab7d}"
  exit 0
fi
exec /usr/bin/git "$@"
GIT
cat > "$mockbin/pkg-config" <<'PKG'
#!/usr/bin/env bash
if [[ "$1" == --exists ]]; then
  [[ "${MOCK_PKGS_OK:-1}" == 1 ]]
  exit
fi
printf '%s\n' "-I$PREBUILT/include -L$PREBUILT/lib -lgbinder -lglib-2.0"
PKG
cat > "$mockbin/file" <<'FILE'
#!/usr/bin/env bash
arch="${MOCK_ARCH:-aarch64}"
[[ "${@: -1}" == */lib64/* ]] && arch="${MOCK_LIB_ARCH:-aarch64}"
if [[ "$arch" == aarch64 ]]; then
  printf '%s: ELF 64-bit LSB pie executable, ARM aarch64, dynamically linked\n' "${@: -1}"
else
  printf '%s: ELF 64-bit LSB pie executable, x86-64, dynamically linked\n' "${@: -1}"
fi
FILE
cat > "$mockbin/readelf" <<'READELF'
#!/usr/bin/env bash
if [[ "$1" == -d ]]; then
  printf '%s\n' "${MOCK_DYNAMIC:- 0 (NEEDED) Shared library: [libgbinder.so]
 0 (NEEDED) Shared library: [libglib-2.0.so]}"
fi
READELF
chmod +x "$mockbin"/*
export PATH="$mockbin:$PATH" PREBUILT="$prebuilt"

if MOCK_ARCH=x86_64 "$builder" --verify-only "$src" "$prebuilt" "$binary" >/dev/null 2>&1; then
  echo 'FAIL: accepted non-AArch64 bluebinder binary' >&2
  exit 1
fi

if MOCK_LIB_ARCH=x86_64 "$builder" --verify-only "$src" "$prebuilt" "$binary" >/dev/null 2>&1; then
  echo 'FAIL: accepted host-architecture bundled runtime library' >&2
  exit 1
fi

if MOCK_GIT_REV=wrong "$builder" --verify-only "$src" "$prebuilt" "$binary" >/dev/null 2>&1; then
  echo 'FAIL: accepted bluebinder at wrong commit' >&2
  exit 1
fi

if MOCK_PKGS_OK=0 "$builder" --verify-only "$src" "$prebuilt" "$binary" >/dev/null 2>&1; then
  echo 'FAIL: accepted missing libgbinder/GLib target package metadata' >&2
  exit 1
fi

if MOCK_DYNAMIC=' 0 (NEEDED) Shared library: [libgbinder.so]
 0 (NEEDED) Shared library: [libglib-2.0.so]
 0 (RPATH) Library rpath: [/usr/lib/x86_64-linux-gnu]' \
  "$builder" --verify-only "$src" "$prebuilt" "$binary" >/dev/null 2>&1; then
  echo 'FAIL: accepted host-only runtime path' >&2
  exit 1
fi

"$builder" --verify-only "$src" "$prebuilt" "$binary"
echo 'Bluebinder artifact contract tests passed'
