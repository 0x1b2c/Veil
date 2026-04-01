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
6. Run `make release V=<version>` — this bumps `MARKETING_VERSION` in the Xcode project and commits
7. Create an annotated tag. The tag message is **only** the bullet list — no title line, because the CI release job sets the GitHub Release title to `Veil v<version>` automatically:
   ```
   git tag -a v<version> -m "<bullet list>"
   ```
8. Push:
   ```
   git push origin master --tags
   ```
   CI builds a universal binary, packages Veil.zip, and creates the GitHub Release.
9. Show the release URL: `https://github.com/rainux/Veil/releases/tag/v<version>`

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
