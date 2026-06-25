#!/usr/bin/env bash

set -euxo pipefail

export WASM_SO_OPT="--debuginfo --low-memory-unused --strip-dwarf -Oz"

MAIN_DYNLIB_DIR="dist-newstyle/build/wasm32-wasi/$(wasm32-wasi-cabal path --compiler-info | awk '/^compiler-id:/ {print $2}')/hint-in-browser-0.1.0.0/build"
TMP_BUILD_DIR="$(mktemp -d --suffix=hint-in-browser-rootfs)"

wasm32-wasi-cabal build

mkdir -p "$TMP_BUILD_DIR/tmp/hslib"
cp --no-preserve=mode -r "$(wasm32-wasi-ghc --print-libdir)" "$TMP_BUILD_DIR/tmp/hslib/lib"

cp --no-preserve=mode -r "$(dirname "$(which wasm32-wasi-clang)")"/../share/wasi-sysroot/lib/wasm32-wasi "$TMP_BUILD_DIR/tmp/clib"

GHC_ENV="$(wasm32-wasi-cabal exec -- sh -c 'cat $GHC_ENVIRONMENT')"
mapfile -t PKG_DBS < <(echo "$GHC_ENV" | awk '/^package-db/ {print $2}')
mapfile -t PKG_IDS < <(echo "$GHC_ENV" | awk '/^package-id/ {print $2}')

PKG_DB_ARGS=()
for db in "${PKG_DBS[@]}"; do
    PKG_DB_ARGS+=(--package-db="$db")
done

DYN_LIB_DIRS=()

for pkgid in "${PKG_IDS[@]}"; do
    # may fail to find boot libraries. this is fine because they are in libdir, so we suppress failure with echo ''
    for dir in $(wasm32-wasi-ghc-pkg "${PKG_DB_ARGS[@]}" field --unit-id "$pkgid" dynamic-library-dirs --simple-output || echo ''); do
        # have to preserve absolute paths for cabal packages
        mkdir -p "$TMP_BUILD_DIR/$(dirname "$dir")"
        cp --no-preserve=mode -r "$dir" "$TMP_BUILD_DIR/$(dirname "$dir")"
        DYN_LIB_DIRS+=("$dir")
    done
done

# Remove unneeded files
find "$TMP_BUILD_DIR" "(" \
    -name "*.hi" \
    -o -name "*.a" \
    -o -name "*.p_hi" \
    -o -name "libHS*_p.a" \
    -o -name "*.p_dyn_hi" \
    -o -name "libHS*_p*.so" \
    -o -name "libHSrts*_debug*.so" \
    ")" -delete
rm -rf \
    "$TMP_BUILD_DIR/tmp/hslib/lib/doc" \
    "$TMP_BUILD_DIR/tmp/hslib/lib/html" \
    "$TMP_BUILD_DIR/tmp/hslib/lib/latex" \
    "$TMP_BUILD_DIR/tmp/hslib/lib/*.mjs" \
    "$TMP_BUILD_DIR/tmp/hslib/lib/*.js" \
    "$TMP_BUILD_DIR/tmp/hslib/lib/*.txt"

wasm32-wasi-ghc-pkg --no-user-package-db --global-package-db="$TMP_BUILD_DIR/tmp/hslib/lib/package.conf.d" unregister Cabal Cabal-syntax
wasm32-wasi-ghc-pkg --no-user-package-db --global-package-db="$TMP_BUILD_DIR/tmp/hslib/lib/package.conf.d" recache
HS_SEARCHDIR="$(find "$TMP_BUILD_DIR/tmp/hslib/lib" -name "*.so" -print0 | xargs -0 -n1 dirname | sort -u | sed "s|^$TMP_BUILD_DIR/|/|")"
rm -rf "$TMP_BUILD_DIR$HS_SEARCHDIR"/*Cabal*

find "$TMP_BUILD_DIR/tmp/clib" -type f -follow ! -name "*.so" -delete
rm -f \
    "$TMP_BUILD_DIR/tmp/clib/libsetjmp.so" \
    "$TMP_BUILD_DIR/tmp/clib/libwasi-emulated-*.so"

# Write a custom GHC env file 
echo 'clear-package-db' > "$TMP_BUILD_DIR/tmp/ghc_env"
echo 'global-package-db' >> "$TMP_BUILD_DIR/tmp/ghc_env"

mkdir -p "$TMP_BUILD_DIR/tmp/pkgdbs"
for pkgdb in "${PKG_DBS[@]}"; do
    cp --no-preserve=mode -r "$pkgdb" "$TMP_BUILD_DIR/tmp/pkgdbs"
    echo "package-db /tmp/pkgdbs/$(basename "$pkgdb")" >> "$TMP_BUILD_DIR/tmp/ghc_env"
done

for pkgid in "${PKG_IDS[@]}"; do
    echo "package-id $pkgid" >> "$TMP_BUILD_DIR/tmp/ghc_env"
done

tar --zstd -hcf www/public/rootfs.tar.zst -C "$TMP_BUILD_DIR" .

mkdir -p www/generated
touch www/generated/constants.js

echo "export const HS_SEARCH_DIR = \"$HS_SEARCHDIR\";" >> www/generated/constants.mjs

MAIN_PKG_SO_PATH="$(realpath "$(find "$MAIN_DYNLIB_DIR" -type f -name "*.so" -print0)")"
echo "export const MAIN_SO_PATH = \"$MAIN_PKG_SO_PATH\";" >> www/generated/constants.mjs
echo "export const MAIN_SO_BASE_NAME = \"$(basename "$MAIN_PKG_SO_PATH")\";" >> www/generated/constants.mjs

echo "export const CABAL_DYN_LIB_DIRS = [$(printf '\"%s\", ' "${DYN_LIB_DIRS[@]}")]" >> www/generated/constants.mjs

# Add other necessary js modules
mkdir -p www/ghc
cp --no-preserve=mode "$(wasm32-wasi-ghc --print-libdir)"/dyld.mjs www/ghc
cp --no-preserve=mode "$(wasm32-wasi-ghc --print-libdir)"/post-link.mjs www/ghc
cp --no-preserve=mode "$(wasm32-wasi-ghc --print-libdir)"/prelude.mjs www/ghc

rsbuild "$@"
