#!/usr/bin/env bash
# Buduje STATYCZNE libsolv.a + libsolvext.a (z -fPIC, bo H# linkuje je do
# satsolv.hlib jako biblioteki wspoldzielonej) i instaluje do lokalnego
# prefiksu. Potrzebne, gdy system ma tylko libsolv.so (typowo pakiet -dev).
#
# Uzycie:
#   scripts/install-static-libsolv.sh                  # prefiks ~/.hackeros/native/libsolv
#   PREFIX=/opt/solv scripts/install-static-libsolv.sh
#   SOLV_COMPRESSION=1 scripts/install-static-libsolv.sh   # dodatkowo .bz2 i .zst w solv_xfopen
#                                                         #   (wymaga libbz2-dev i libzstd-dev)
# Wymagania: git, cmake, make, kompilator C oraz naglowki:
#   Debian/Ubuntu: apt install git cmake build-essential pkg-config libexpat1-dev zlib1g-dev liblzma-dev
#   Fedora:        dnf install git cmake gcc make pkgconf expat-devel zlib-devel xz-devel
#   Arch:          pacman -S git cmake base-devel expat zlib xz
#   Alpine:        apk add git cmake build-base pkgconf expat-dev zlib-dev xz-dev
# (libsolv sam wymusza zlib, a przy loaderach deb/arch takze lzma — .gz i .xz dzialaja zawsze.)
set -euo pipefail

VERSION="${SOLV_VERSION:-0.7.40}"
PREFIX="${PREFIX:-$HOME/.hackeros/native/libsolv}"
WORK="${WORK:-$(mktemp -d)}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "brak '$1' w PATH — zainstaluj go i uruchom ponownie" >&2; exit 1; }; }
need git; need cmake; need make; need cc

COMP=OFF
[ "${SOLV_COMPRESSION:-0}" = "1" ] && COMP=ON

echo ">> libsolv $VERSION -> $PREFIX (bz2/zstd=$COMP)"
git clone --quiet --depth 1 --branch "$VERSION" https://github.com/openSUSE/libsolv.git "$WORK/libsolv"

cmake -S "$WORK/libsolv" -B "$WORK/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DENABLE_STATIC=ON -DDISABLE_SHARED=ON \
  -DENABLE_RPMMD=ON -DENABLE_DEBIAN=ON -DENABLE_ARCHREPO=ON \
  -DENABLE_COMPS=OFF -DENABLE_SUSEREPO=OFF -DENABLE_HELIXREPO=OFF \
  -DENABLE_RPMDB=OFF -DENABLE_PUBKEY=OFF -DENABLE_APPDATA=OFF \
  -DENABLE_BZIP2_COMPRESSION="$COMP" -DENABLE_ZSTD_COMPRESSION="$COMP" \
  -DWITH_LIBXML2=OFF \
  -DENABLE_PERL=OFF -DENABLE_PYTHON=OFF -DENABLE_RUBY=OFF -DENABLE_TCL=OFF \
  -DENABLE_PYTHON3=OFF -DENABLE_PERL=OFF -DENABLE_LUA=OFF
cmake --build "$WORK/build" -j "$JOBS"
cmake --install "$WORK/build"

for f in libsolv.a libsolvext.a; do
  [ -f "$PREFIX/lib/$f" ] || { echo "BLAD: brak $PREFIX/lib/$f po instalacji" >&2; exit 1; }
done
rm -rf "$WORK"

cat <<MSG

Gotowe: $PREFIX/lib/libsolv.a  $PREFIX/lib/libsolvext.a

Zbuduj satsolv tak:

  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:\${PKG_CONFIG_PATH:-}"
  export LIBRARY_PATH="$PREFIX/lib:\${LIBRARY_PATH:-}"
  export CPATH="$PREFIX/include:\${CPATH:-}"
  bit

(albo wpisz to raz do ~/.bashrc). Mozna tez uzyc: source scripts/env.sh
MSG
