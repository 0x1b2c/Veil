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

set -- ${ARCHS}
if [ $# -gt 1 ]; then
    # `swift build --arch arm64 --arch x86_64` routes through Xcode's
    # build system (xcbuild), which mis-resolves plugin target GUIDs
    # across local-package dependencies and aborts with
    # "missing target with GUID 'PACKAGE-TARGET:BuildVersionPlugin@N'".
    # Per-arch invocations use LLBuild and work, so build each arch
    # separately and lipo them together for the universal binary.
    slices=""
    for arch in "$@"; do
        swift build \
            --package-path "${pkg_dir}" \
            -c release \
            --product veil \
            --arch "${arch}"
        slices="${slices} ${pkg_dir}/.build/${arch}-apple-macosx/release/veil"
    done
    src_bin="${pkg_dir}/.build/veil-universal"
    lipo -create ${slices} -output "${src_bin}"
else
    swift build \
        --package-path "${pkg_dir}" \
        -c release \
        --product veil \
        --arch "$1"
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
