#!/bin/sh
set -eu

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
# builds land under .build/<arch>-apple-macosx/release/. Pick whichever exists
# so the script works under either configuration Xcode hands us.
src_bin="${pkg_dir}/.build/apple/Products/Release/veil"
if [ ! -f "${src_bin}" ]; then
    for arch in ${ARCHS}; do
        candidate="${pkg_dir}/.build/${arch}-apple-macosx/release/veil"
        if [ -f "${candidate}" ]; then
            src_bin="${candidate}"
            break
        fi
    done
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
