# source scripts/env.sh — ustawia sciezki do lokalnie zbudowanego statycznego libsolv
# (patrz scripts/install-static-libsolv.sh). Prefiks mozna nadpisac: PREFIX=/opt/solv
PREFIX="${PREFIX:-$HOME/.hackeros/native/libsolv}"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LIBRARY_PATH="$PREFIX/lib:${LIBRARY_PATH:-}"
export CPATH="$PREFIX/include:${CPATH:-}"
