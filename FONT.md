# Font Configuration

Veil reads font configuration from `~/.config/veil/veil.toml`. Changes apply to windows opened after the file is saved.

## Contents

- [Relationship to `vim.o.guifont`](#relationship-to-vimoguifont)
- [Configuring the font](#configuring-the-font)
- [Recommended font family](#recommended-font-family)
- [Fallback chain](#fallback-chain)

## Relationship to `vim.o.guifont`

On a local connection Veil reads the font from nvim's `vim.o.guifont`, the same way every classic Vim GUI does. The `[font]` block in `veil.toml` exists as a fallback for the cases where nvim doesn't supply a usable value, and as an authoritative override for the cases where reading from nvim isn't appropriate.

The decision rules:

- **Local connection** (default): Veil reads each field from `vim.o.guifont`. Any field nvim doesn't provide (or whose value can't be resolved on this Mac) falls back to the matching field in `[font]`, then to the system monospaced default.
- **Remote connection**: Veil uses `[font]` directly. The remote nvim's `guifont` reflects the remote machine's installed families and display, which rarely matches the local Mac; using `[font]` keeps font choice tied to where the rendering actually happens.
- **Local connection with `force = true`**: nvim's `guifont` is ignored, just as on a remote connection. Set this when you'd rather have Veil use `[font]` on local connections too. The trade-off is that all windows share the same font regardless of which Neovim configuration they run; recommended if you want to simplify your setup and don't need per-profile font differentiation.

An empty `[font]` block has no effect.

## Configuring the font

```toml
[font]
family = "Maple Mono NF CN"
size = 16.0
# force = true     # use [font] on local connections too (no per-profile font)
```

| Field    | Type   | Description                                                              |
| -------- | ------ | ------------------------------------------------------------------------ |
| `family` | string | macOS family display name (e.g. `Menlo`, `SF Mono`), not PostScript      |
| `size`   | float  | Font size in points                                                      |
| `force`  | bool   | If `true`, Veil uses `[font]` on local connections too (default `false`). See trade-off above. |

`family` is the name as it appears in Font Book (so `SF Mono`, not `SFMono-Regular`). If the named family isn't installed, Veil falls back to the system monospaced font and logs a warning to the system log.

All fields are independently optional; any may be omitted.

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
