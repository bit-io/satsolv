#!/usr/bin/env bash
# Wywolywany przez bit (`[build] native` w Bit.hk) PRZED kompilacja satsolv — takze
# gdy satsolv jest zaleznoscia innego pakietu (libhammer, hammer, ...).
# Zapewnia STATYCZNE libsolv.a + libsolvext.a (z -fPIC), bo pakiety -dev dostarczaja
# zwykle tylko libsolv.so, a bit linkuje statycznie ("cannot find -lsolv").
#
# 1. jesli kompilator widzi juz libsolv.a + libsolvext.a (system / LIBRARY_PATH) -> nic nie robi,
# 2. w przeciwnym razie buduje je z zrodel (git + cmake + make + cc) do
#    <katalog pakietu>/.bit/native/libsolv — bit dodaje ten katalog do LIBRARY_PATH
#    (patrz [build] native-lib-path w Bit.hk).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${SATSOLV_PREFIX:-$ROOT/.bit/native/libsolv}"
LIBDIR="$PREFIX/lib"

has_static() {  # $1 = nazwa pliku; szuka w LIBRARY_PATH i w sciezkach kompilatora
  local f="$1" p
  IFS=: read -ra dirs <<< "${LIBRARY_PATH:-}"
  for d in "${dirs[@]}"; do [ -n "$d" ] && [ -f "$d/$f" ] && return 0; done
  p="$(cc -print-file-name="$f" 2>/dev/null || true)"
  [ -n "$p" ] && [ "$p" != "$f" ] && [ -f "$p" ]
}

mkdir -p "$LIBDIR"   # bit ostrzega, gdy katalog z [build] native-lib-path nie istnieje

if [ -f "$LIBDIR/libsolv.a" ] && [ -f "$LIBDIR/libsolvext.a" ]; then exit 0; fi

if has_static libsolv.a && has_static libsolvext.a; then
  echo "satsolv: statyczne libsolv.a/libsolvext.a znalezione w systemie — nic do budowania"
  exit 0
fi

missing=""
for t in git cmake make cc; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
if [ -n "$missing" ]; then
  cat >&2 <<MSG
satsolv: brak statycznego libsolv.a, a do zbudowania go brakuje narzedzi:$missing
  Debian/Ubuntu: sudo apt install git cmake build-essential pkg-config libexpat1-dev zlib1g-dev liblzma-dev
  Fedora:        sudo dnf install git cmake gcc make pkgconf expat-devel zlib-devel xz-devel
  Arch:          sudo pacman -S git cmake base-devel expat zlib xz
  Alpine:        sudo apk add git cmake build-base pkgconf expat-dev zlib-dev xz-dev
Potem uruchom bit ponownie.
MSG
  exit 1
fi

echo "satsolv: buduje statyczne libsolv.a / libsolvext.a -> $LIBDIR"
PREFIX="$PREFIX" "$ROOT/scripts/install-static-libsolv.sh"
