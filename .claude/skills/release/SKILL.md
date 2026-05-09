---
name: release
description: Release a new version of Veil — bump version, write release notes, create annotated tag, and push to trigger CI. Use when the user says "发布", "release", or "/release 0.5".
allowed-tools: Bash(git:*) Bash(make:*) Bash(gh:*) Read Edit
---

# Release a New Version

## Arguments

Required: version number (e.g., `/release 0.5`).

## Procedure

1. If no version number is provided, ask the user and stop
2. Verify the working tree is clean (`git status`). If there are uncommitted changes, warn the user and stop
3. Collect all commits since the last tag:
   ```
   git log $(git describe --tags --abbrev=0)..HEAD --oneline
   ```
4. Write release notes from those commits:
   - User-visible features and fixes only — skip internal refactoring, CI changes, code cleanup
   - One line per item, starting with `- `
   - English, concise, describes what changed from the user's perspective
   - Features first, then fixes (prefix fixes with "Fix")
5. Show the release notes to the user and **wait for confirmation** before proceeding
6. Write the confirmed bullet list to a temp file and call `make release` to atomically bump `MARKETING_VERSION`, commit, and create the annotated tag in one step. The tag message is **only** the bullet list — no title line, because the CI release job sets the GitHub Release title to `Veil v<version>` automatically:
   ```
   notes_file=$(mktemp -t veil-release-notes)
   cat > "$notes_file" <<'NOTES'
   <bullet list>
   NOTES
   make release V=<version> NOTES_FILE="$notes_file"
   rm -f "$notes_file"
   ```
7. Verify the tag commit is exactly HEAD before pushing — catches any drift between the pbxproj bump commit and the tag:
   ```
   [ "$(git describe --tags --exact-match HEAD)" = "v<version>" ] || { echo "ERROR: HEAD is not the v<version> tag commit"; exit 1; }
   ```
8. Push:
   ```
   git push origin master --tags
   ```
   CI builds a universal binary, packages Veil.zip, and creates the GitHub Release.
9. Wait for CI to finish, then update the Homebrew cask:
   - Wait for the release workflow to complete:
     ```
     gh run watch -R 0x1b2c/Veil $(gh run list -R 0x1b2c/Veil -w Build --limit 1 --json databaseId -q '.[0].databaseId')
     ```
   - Download the release zip and compute SHA256:
     ```
     gh release download v<version> -R 0x1b2c/Veil -p Veil.zip -D /tmp && shasum -a 256 /tmp/Veil.zip
     ```
   - Update `homebrew-veil/Casks/veil.rb` with the new version and sha256
   - Commit and push the homebrew-veil repo:
     ```
     git -C homebrew-veil commit -am "Update to v<version>"
     git -C homebrew-veil push
     ```
10. Show the release URL: `https://github.com/0x1b2c/Veil/releases/tag/v<version>`

## Release notes examples

Good (user perspective, concise):

```
- Metal GPU-accelerated grid rendering
- Title bar colors adapt to neovim colorscheme
- Fix CJK double-width characters partially covered on cursor line
```

Bad (implementation details, commit-style):

```
- Add MetalRenderer.swift with vertex buffer and glyph atlas
- Update WindowController.swift to cache fg/bg in UserDefaults
- fix: resolve overlay rendering issue
```

## Critical constraints

- **NEVER** proceed past step 5 without user confirmation of the release notes
- **NEVER** force push
- Tag message must NOT contain a title line — the CI workflow's `name: Veil ${{ github.ref_name }}` handles the GitHub Release title
- **NEVER** use `cd <dir> && git ...` — use `git -C <dir>` instead
