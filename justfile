# Build, test, package and release Veil. Builds never sign; signing happens
# only when a bundle is installed or packaged, see Tools/sign-adhoc.sh.

project := "Veil.xcodeproj"
scheme := "Veil"
# Single-arch destination for fast local builds on Apple Silicon.
# Specifying arch keeps xcodebuild from matching multiple "My Mac" entries.
dest := "platform=macOS,arch=arm64"
# Generic destination for universal binary builds (no specific machine).
dest_universal := "generic/platform=macOS"
derived := ".build"
app := derived / "Build/Products/Release/Veil.app"
# Where Veil.app goes; override with `just install_dir=$HOME/Applications install`.
install_dir := "/Applications"
universal := "ONLY_ACTIVE_ARCH=NO"
no_profiling := "CLANG_ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO"
# Match CI behavior so locally-built zips have the same linker-applied
# ad-hoc signature as what ships on Releases. Without this, xcodebuild
# falls back to "Sign to Run Locally" and produces a binary with
# hardened runtime and a CFBundleIdentifier-derived code identity,
# which diverges from the released artifact.
no_signing := "CODE_SIGNING_ALLOWED=NO"
xcodebuild := "xcodebuild -project " + project + " -scheme " + scheme + " -destination '" + dest + "'"
xcodebuild_universal := "xcodebuild -project " + project + " -scheme " + scheme + " -destination '" + dest_universal + "'"
lsregister := "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

# Release build for this Mac, arm64 only (fast).
build:
    {{ xcodebuild }} -configuration Release -derivedDataPath {{ derived }} {{ no_profiling }} {{ no_signing }} -quiet
    @echo "Built: {{ app }}"

# Release build as a universal binary (arm64 and x86_64), as shipped.
build-universal:
    {{ xcodebuild_universal }} -configuration Release -derivedDataPath {{ derived }} {{ universal }} {{ no_profiling }} {{ no_signing }} -quiet
    @echo "Built (universal): {{ app }}"

# Build only the bundled veil CLI with SwiftPM.
cli:
    swift build --package-path Packages/veil -c release --product veil
    @echo "Built: Packages/veil/.build/release/veil"

# Debug build for this Mac.
debug:
    {{ xcodebuild }} -configuration Debug -derivedDataPath {{ derived }} -quiet

# Apple's xcodebuild emits per-test "Test case ... passed/failed" lines but
# no aggregate summary, so we synthesize one. The "no tests ran" branch is
# a sanity check: if xcodebuild changes its prefix again (it has before),
# the count would silently drop to 0 and look like success without it.
# Assertion details aren't in the stdout log; open the .xcresult bundle in
# Xcode or use xcrun xcresulttool to inspect them.
# Run the SPM and xcodebuild tests and print a PASS/FAIL summary.
test:
    #!/usr/bin/env bash
    set -euo pipefail
    swift test --package-path Packages/VeilCore --quiet
    out="{{ derived }}/test.log"
    mkdir -p "{{ derived }}"
    status=0
    {{ xcodebuild }} -derivedDataPath {{ derived }} -only-testing:VeilTests {{ no_signing }} test -quiet > "$out" 2>&1 || status=$?
    passed=$(grep -cE "^Test case .* passed" "$out" || true)
    failed=$(grep -cE "^Test case .* failed" "$out" || true)
    if [ "$failed" -gt 0 ]; then
        echo "FAIL: $failed failed, $passed passed"
        grep -E "^Test case .* failed" "$out" | sed -E "s/^Test case '([^']+)' failed.*/  ✖ \1/"
        echo "  (full log: $out)"
        exit 1
    elif [ "$status" -ne 0 ]; then
        echo "FAIL: build or infrastructure error"
        grep -E "error: " "$out" | head -10 || true
        echo "  (full log: $out)"
        exit "$status"
    elif [ "$passed" -eq 0 ]; then
        echo "WARN: no tests ran — xcodebuild output format may have changed"
        echo "  (full log: $out)"
        exit 1
    else
        echo "PASS: $passed tests"
    fi

# Run the tests with xcodebuild's own output and no summary.
test-verbose:
    swift test --package-path Packages/VeilCore
    {{ xcodebuild }} -derivedDataPath {{ derived }} -only-testing:VeilTests {{ no_signing }} test -quiet

# Remove build products and packaged zips, and unregister the built app.
clean:
    {{ xcodebuild }} clean -quiet
    {{ lsregister }} -u {{ app }} 2>/dev/null || true
    rm -rf {{ derived }} Packages/VeilCore/.build Packages/veil/.build
    rm -f Veil.zip Veil-default-editor.zip

# TCC binds permission grants (Full Disk Access, folder access) to the
# app's designated requirement, and linker-signed builds have no DR at
# all, so grants fail outright on current macOS. Tools/sign-adhoc.sh
# re-signs the bundle with an identifier-based DR that every future
# build satisfies, keeping user grants valid across upgrades. It runs
# at packaging/install time, after any Info.plist edits (which would
# break an earlier seal), never inside build/build-universal.
# Build, sign and install Veil.app into install_dir.
install: build
    Tools/sign-adhoc.sh "{{ app }}"
    rsync -a --delete "{{ app }}/" "{{ install_dir }}/Veil.app/"
    @echo "Installed to {{ install_dir }}/Veil.app"

# Build, sign and install the polite variant, which strips LSHandlerRank.
install-polite: build
    Tools/make-bundle-polite.sh "{{ app }}"
    Tools/sign-adhoc.sh "{{ app }}"
    rsync -a --delete "{{ app }}/" "{{ install_dir }}/Veil.app/"
    @echo "Installed polite variant to {{ install_dir }}/Veil.app"

# Universal build packaged as Veil-default-editor.zip (claims file associations).
zip: build-universal
    Tools/sign-adhoc.sh "{{ app }}"
    ditto -c -k --keepParent --norsrc --noextattr --noacl "{{ app }}" Veil-default-editor.zip
    @echo "Packaged: Veil-default-editor.zip"

# Universal build packaged as Veil.zip, the polite variant.
zip-polite: build-universal
    #!/usr/bin/env bash
    set -euo pipefail
    work=$(mktemp -d)
    ditto "{{ app }}" "$work/Veil.app"
    Tools/make-bundle-polite.sh "$work/Veil.app"
    Tools/sign-adhoc.sh "$work/Veil.app"
    ditto -c -k --keepParent --norsrc --noextattr --noacl "$work/Veil.app" Veil.zip
    rm -rf "$work"
    echo "Packaged: Veil.zip"

# Generate buildServer.json for SourceKit-LSP (requires xcode-build-server).
lsp:
    xcode-build-server config -project {{ project }} -scheme {{ scheme }} --build_root {{ derived }}

# Bumps MARKETING_VERSION, commits, and creates an annotated tag in one
# atomic step so the tag commit physically carries the matching pbxproj
# value. Verifies the sed actually landed before committing: if pbxproj's
# format ever changes and the substitution silently no-ops, the build
# would otherwise ship with the old version stamped into Info.plist.
# Bump the version, commit and tag: `just release 0.8.3 /path/to/notes.md`.
release version notes_file:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "{{ notes_file }}" || { echo "ERROR: notes file not found: {{ notes_file }}"; exit 1; }
    sed -i '' 's/MARKETING_VERSION = [^;]*/MARKETING_VERSION = {{ version }}/' {{ project }}/project.pbxproj
    total=$(grep -cE 'MARKETING_VERSION = ' {{ project }}/project.pbxproj || true)
    ok=$(grep -cE 'MARKETING_VERSION = {{ version }};' {{ project }}/project.pbxproj || true)
    if [ "$total" != "$ok" ] || [ "$total" -eq 0 ]; then
        echo "ERROR: sed left $ok of $total MARKETING_VERSION lines at {{ version }}; reverting pbxproj"
        git checkout -- {{ project }}/project.pbxproj
        exit 1
    fi
    git add {{ project }}/project.pbxproj
    git commit -m "Release v{{ version }}"
    # --cleanup=verbatim preserves Markdown section headers like `## Features`
    # in the tag annotation. Git's default cleanup mode treats `#` as a comment
    # leader and strips those lines, which would silently drop the section
    # structure that the GitHub Release body inherits from the tag.
    git tag -a v{{ version }} -F "{{ notes_file }}" --cleanup=verbatim
    echo "Tagged v{{ version }}. To publish: git push origin master --tags"

# Machine-specific recipes (deploying to particular hosts and install paths)
# live in an uncommitted justfile.local next to this file, imported when present.
import? 'justfile.local'
