#!/bin/sh
set -eu

# Converts a Veil .app bundle into the "polite" variant in-place by
# stripping LSHandlerRank from every CFBundleDocumentTypes entry in
# Info.plist. Same binary, same bundle ID, same name; only the plist
# differs. Without LSHandlerRank, LaunchServices treats Veil as a
# non-default candidate for the registered file types; it appears in
# "Open With" but never claims the default association.
#
# The bundle is left with its original linker-applied ad-hoc signature
# (consistent with how Veil has shipped since v0.6). Running `codesign`
# here would mutate the binary's embedded identifier and balloon its
# size by ~50KB for no functional benefit.

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path-to-Veil.app>" >&2
    exit 1
fi

APP="$1"
INFO="$APP/Contents/Info.plist"

if [ ! -d "$APP" ]; then
    echo "ERROR: $APP not found." >&2
    exit 1
fi

if [ ! -f "$INFO" ]; then
    echo "ERROR: Info.plist not found at $INFO." >&2
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

echo "Stripped LSHandlerRank from $i CFBundleDocumentTypes entries in $APP"
