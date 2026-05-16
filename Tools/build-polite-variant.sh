#!/bin/sh
set -eu

# Post-processes Veil-default-editor.zip into Veil.zip by stripping
# LSHandlerRank = Default from every CFBundleDocumentTypes entry in
# Info.plist, then re-signing the bundle ad-hoc. Same binary, same
# bundle ID, same name; only the plist differs. Without LSHandlerRank,
# LaunchServices treats Veil as a non-default candidate for the
# registered file types; it appears in "Open With" but never claims
# the default association.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SOURCE_ZIP="$PROJECT_DIR/Veil-default-editor.zip"
OUTPUT_ZIP="$PROJECT_DIR/Veil.zip"

if [ ! -f "$SOURCE_ZIP" ]; then
    echo "ERROR: $SOURCE_ZIP not found. Run 'make zip' first." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

ditto -x -k "$SOURCE_ZIP" "$WORK_DIR"

APP="$WORK_DIR/Veil.app"
INFO="$APP/Contents/Info.plist"

if [ ! -f "$INFO" ]; then
    echo "ERROR: Info.plist not found at $INFO after extraction." >&2
    exit 1
fi

# Iterate until PlistBuddy errors out. Hardcoding indices would silently
# miss entries added in the future. Delete is idempotent: entries that
# already lack LSHandlerRank are skipped without error.
i=0
while /usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes:$i" "$INFO" >/dev/null 2>&1; do
    /usr/libexec/PlistBuddy -c "Delete :CFBundleDocumentTypes:$i:LSHandlerRank" "$INFO" 2>/dev/null || true
    i=$((i + 1))
done

if [ "$i" -eq 0 ]; then
    echo "ERROR: No CFBundleDocumentTypes entries found in $INFO." >&2
    exit 1
fi

# Patching Info.plist invalidates the original code signature. Re-sign
# ad-hoc; the project does not use Developer ID.
codesign --force --sign - --deep "$APP"

rm -f "$OUTPUT_ZIP"
ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP" "$OUTPUT_ZIP"

echo "Packaged: $OUTPUT_ZIP ($i CFBundleDocumentTypes processed)"
