#!/bin/sh
set -eu

# Fallbacks let the script run standalone (without xcodebuild) for timing,
# debugging, or A/B comparisons. When invoked as a Run Script build phase
# Xcode supplies all five variables and overrides every default below.
: "${SRCROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
: "${ARCHS:=$(uname -m)}"
: "${BUILT_PRODUCTS_DIR:=/tmp/veil-cli-standalone}"
: "${CONTENTS_FOLDER_PATH:=Veil.app/Contents}"
: "${EXPANDED_CODE_SIGN_IDENTITY:=-}"

mkdir -p "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin"

cli_bin="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin/veil"
rm -f "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin/veil-client"

pkg_dir="${SRCROOT}/Packages/veil"
arch_args=""
for arch in ${ARCHS}; do
    arch_args="${arch_args} --arch ${arch}"
done

swift build \
    --package-path "${pkg_dir}" \
    -c release \
    --product veil \
    ${arch_args}

# Multi-arch SPM builds land under .build/apple/Products/Release/. Single-arch
# builds land under .build/<arch>-apple-macosx/release/. Pick the path that
# matches the current ARCHS, otherwise a stale multi-arch binary left over
# from a previous `make zip` could shadow the fresh single-arch output of
# `make build`.
set -- ${ARCHS}
if [ $# -gt 1 ]; then
    src_bin="${pkg_dir}/.build/apple/Products/Release/veil"
else
    src_bin="${pkg_dir}/.build/$1-apple-macosx/release/veil"
fi

cp "${src_bin}" "${cli_bin}"
chmod +x "${cli_bin}"

if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${cli_bin}"
else
    codesign --force --sign - --timestamp=none "${cli_bin}"
fi

ln -sf veil "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin/gvim"
ln -sf veil "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin/gvimdiff"
