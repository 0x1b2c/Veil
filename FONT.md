# Font Configuration

Veil reads font configuration from `~/.config/veil/veil.toml`. Changes apply to windows opened after the file is saved.

## Contents

- [Relationship to `vim.o.guifont`](#relationship-to-vimoguifont)
- [Configuring the font](#configuring-the-font)
- [Recommended font family](#recommended-font-family)
- [Fallback chain](#fallback-chain)

## Relationship to `vim.o.guifont`

By default Veil reads the font from nvim's `vim.o.guifont`, the same way every classic Vim GUI does. The `[font]` block in `veil.toml` exists for cases where reading from nvim isn't appropriate. The most important such case is remote mode: when Veil connects to a remote nvim, that nvim's `guifont` reflects the remote machine's preferences (its installed families, its display) rather than your local Mac's, and the named font may not even exist locally.

When `[font]` is present, the merge is per-field. A field set in `[font]` overrides the corresponding field from `guifont`; an unset field falls through. Setting only `family` means nvim's `guifont` still controls size; setting only `size` means it still controls family. An empty `[font]` block has no effect at all. The merge runs at window startup and on every `guifont` event from nvim.

## Configuring the font

```toml
[font]
family = "Maple Mono NF CN"
size = 16.0
```

| Field    | Type   | Description                                                         |
| -------- | ------ | ------------------------------------------------------------------- |
| `family` | string | macOS family display name (e.g. `Menlo`, `SF Mono`), not PostScript |
| `size`   | float  | Font size in points                                                 |

`family` is the name as it appears in Font Book (so `SF Mono`, not `SFMono-Regular`). If the named family isn't installed, Veil falls back to the system monospaced font and logs a warning to the system log.

Both fields are independently optional; either or both may be omitted.

## Recommended font family

We recommend [Maple Mono](https://github.com/subframe7536/maple-font) for its Nerd Font icons and CJK variants. The variant suffix tells you what's bundled:

- `Maple Mono NF`: base family with Nerd Font icons (`brew install font-maple-mono-nf`)
- `Maple Mono NF CN`: also adds CJK coverage (`brew install font-maple-mono-nf-cn`)

Pick the `CN` variant if you write any CJK; otherwise `NF` is sufficient.

## Fallback chain

When the primary font lacks a glyph for some text, Veil walks this chain in order:

1. **Same-family CJK companion**: if your primary is `Foo NF`, Veil also tries `Foo NF CN`, `Foo NF SC`, `Foo NF TC`, `Foo NF JP`, `Foo NF KR`, `Foo NF HK`. This matches font families that ship as a base plus regional CJK variants.
2. **Installed Nerd Font**: at startup Veil probes for any installed Nerd Font and uses it for icon glyphs the primary doesn't cover.
3. **macOS system fallback**: CoreText's own glyph fallback (PingFang for Chinese, Hiragino for Japanese, Apple SD Gothic Neo for Korean, Apple Color Emoji for emoji, etc.).

All fallback fonts are rescaled to match the primary's cap height, so mixed-glyph lines render at consistent visual size.
