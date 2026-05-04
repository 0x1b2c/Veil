#!/bin/sh
set -eu

mkdir -p "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin" "${DERIVED_FILE_DIR}"

cli_bin="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin/veil"
rm -f "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin/veil-client"

cli_slices=""
for arch in ${ARCHS}; do
    arch_bin="${DERIVED_FILE_DIR}/veil-cli-${arch}"
    xcrun swiftc \
        -parse-as-library \
        -target "${arch}-apple-macos${MACOSX_DEPLOYMENT_TARGET}" \
        "${SRCROOT}/Shared/CommandLineArguments.swift" \
        "${SRCROOT}/Shared/AppleEventProtocol.swift" \
        "${SRCROOT}/CLI/veil/main.swift" \
        -o "${arch_bin}" \
        -framework AppKit
    cli_slices="${cli_slices} ${arch_bin}"
done

xcrun lipo -create ${cli_slices} -output "${cli_bin}"
chmod +x "${cli_bin}"

if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${cli_bin}"
else
    codesign --force --sign - --timestamp=none "${cli_bin}"
fi

ln -sf veil "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin/gvim"
ln -sf veil "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin/gvimdiff"
