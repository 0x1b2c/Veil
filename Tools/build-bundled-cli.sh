#!/bin/sh
set -eu

# Fallbacks let the script run standalone (without xcodebuild) for timing,
# debugging, or A/B comparisons. When invoked as a Run Script build phase
# Xcode supplies all four variables and overrides every default below.
: "${SRCROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
: "${ARCHS:=$(uname -m)}"
: "${BUILT_PRODUCTS_DIR:=/tmp/veil-cli-standalone}"
: "${CONTENTS_FOLDER_PATH:=Veil.app/Contents}"

mkdir -p "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin"

cli_bin="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin/veil"
rm -f "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin/veil-client"

pkg_dir="${SRCROOT}/Packages/veil"

# Runs on every build with no input/output declarations: the CLI embeds
# `git describe` through BuildVersionPlugin, so a new commit changes the
# binary even when no source file does, and only swift build can tell.

# Build one architecture into its own scratch directory and print the
# path of the resulting binary. Each arch gets a separate scratch path
# because the build system behind recent toolchains (Swift Build) writes
# every arch of a configuration to the same Products directory, so a
# second arch would overwrite the first; separate directories also keep
# each arch's incremental state, so alternating single-arch and universal
# builds never forces a rebuild. The script asks SwiftPM for the output
# location instead of assuming it: the layout differs between build systems,
# and a guessed path can silently point at a stale binary left over from
# an older toolchain.
build_arch() {
    arch="$1"
    scratch="${pkg_dir}/.build/cli-${arch}"
    swift build \
        --package-path "${pkg_dir}" \
        --scratch-path "${scratch}" \
        -c release \
        --product veil \
        --arch "${arch}" >&2 || return 1
    bin_dir=$(swift build \
        --package-path "${pkg_dir}" \
        --scratch-path "${scratch}" \
        -c release \
        --product veil \
        --arch "${arch}" \
        --show-bin-path) || return 1
    printf '%s/veil\n' "${bin_dir}"
}

set -- ${ARCHS}
if [ $# -gt 1 ]; then
    # Build each arch separately and lipo the slices together. On older
    # toolchains (Xcode 16, CI's macos-15 runner) a single
    # `swift build --arch arm64 --arch x86_64` routes through xcbuild,
    # which mis-resolves plugin target GUIDs across local-package
    # dependencies and aborts. Swift Build (Xcode 27) builds a universal
    # binary in one invocation; once CI runs on such a toolchain this
    # branch can collapse into that single call.
    #
    # Slice paths are appended to the positional parameters behind the arch
    # names (the loop's word list is already expanded, so this is safe) and
    # the arch names are shifted off afterwards. Joining the paths into one
    # string and expanding it unquoted would split a path containing spaces.
    arch_count=$#
    for arch in "$@"; do
        slice=$(build_arch "${arch}") || exit 1
        set -- "$@" "${slice}"
    done
    shift "${arch_count}"
    src_bin="${pkg_dir}/.build/veil-universal"
    lipo -create "$@" -output "${src_bin}"
else
    src_bin=$(build_arch "$1") || exit 1
fi

cp "${src_bin}" "${cli_bin}"
chmod +x "${cli_bin}"

# `swift build` leaves the binary with a linker-applied ad-hoc signature,
# which is only a placeholder: Tools/sign-adhoc.sh re-signs the CLI (and
# the whole bundle) with the identifier-based designated requirement at
# packaging/install time. Don't run `codesign` here; a signature applied
# now would be replaced anyway, and signing must happen after the bundle
# contents are final.

ln -sf veil "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin/gvim"
ln -sf veil "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/bin/gvimdiff"
