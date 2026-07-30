#!/bin/sh
set -eu

# Re-signs a Veil .app bundle ad-hoc with an identifier-based designated
# requirement (DR). TCC binds permission grants (Full Disk Access, folder
# access) to the app's DR, not to its path. The linker-applied ad-hoc
# signature on CODE_SIGNING_ALLOWED=NO builds carries no requirements
# section at all, so TCC cannot record a usable requirement and grants
# silently fail on current macOS. Signing with a fixed identifier DR
# gives TCC a requirement that every future build satisfies, so grants
# survive upgrades. (See the corresponding entry in DECISIONS.md.)
#
# Two steps to avoid the deprecated --deep flag: the bundled CLI is a
# nested Mach-O that must carry a valid signature before the outer
# bundle is sealed, so it is signed first. gvim/gvimdiff beside it are
# symlinks to it and need no signing. Ad-hoc signatures contain no
# certificate and are machine-independent, so signing at packaging or
# install time survives zip/download/unzip.

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path-to-Veil.app>" >&2
    exit 1
fi

APP="$1"
CLI="$APP/Contents/bin/veil"

if [ ! -d "$APP" ]; then
    echo "ERROR: $APP is not an app bundle directory." >&2
    exit 1
fi

if [ ! -f "$CLI" ]; then
    echo "ERROR: bundled CLI not found at $CLI." >&2
    exit 1
fi

codesign -fs - "$CLI"
codesign -fs - -r='designated => identifier "org.1b2c.Veil"' "$APP"

echo "Signed $APP with designated requirement: identifier \"org.1b2c.Veil\""
