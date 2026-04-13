# Keyboard Configuration

Veil's keyboard shortcuts are configurable through `~/.config/veil/veil.toml`. This document describes the configuration format, available key names, and how to customize or disable Veil's default keybindings.

## Overview

Veil splits its keyboard shortcuts into two categories:

1. **Veil-owned actions**: window management, menu actions, and Veil-specific workflows (opening a new window, connecting to remote nvim, etc.). These actions require native macOS GUI code and can only be executed by Veil itself. You can rebind them to different shortcuts or disable their shortcuts entirely, but the actions themselves always belong to Veil. When a shortcut is disabled, the corresponding menu item remains visible and clickable — only the keyboard shortcut is removed.

2. **Default Vim keymaps**: convenience mappings where Veil intercepts common macOS shortcuts (Cmd+S, Cmd+Z, Cmd+1-9, etc.) and forwards them to Neovim commands (`:w`, `u`, `:tabnext`, etc.). These are a batteries-included default so Veil feels like a normal macOS editor out of the box. A single switch (`bind_default_keymaps`) toggles the entire set. When you disable it, all these keys pass through to Neovim as `<D-s>`, `<D-1>`, etc., and you define your own mappings in your nvim config.

The philosophy: you own your keymap. Veil provides sensible defaults, but you can take over any part of the binding at any time.

## Shortcut String Format

Shortcuts are written as `+`-separated tokens:

```
cmd+shift+n
ctrl+tab
shift+cmd+}
```

**Rules:**

- Tokens are separated by `+`
- Whitespace around `+` is tolerated (`cmd + shift + n` parses the same as `cmd+shift+n`)
- Modifier names and named keys are case-insensitive (`CMD+Tab`, `cmd+tab` are equivalent)
- Exactly one non-modifier key per shortcut (no chord shortcuts like `Ctrl+K Ctrl+C`)
- Empty string (`""`) means "disabled"

**Modifiers:**

| Name        | Meaning        |
| ----------- | -------------- |
| `cmd`       | ⌘ Command      |
| `ctrl`      | ⌃ Control      |
| `shift`     | ⇧ Shift        |
| `alt`       | ⌥ Option / Alt |
| `option`    | Alias for `alt`|

### Shifted Punctuation

This is the one place where the format has a quirk worth knowing about. Cocoa's `NSEvent.charactersIgnoringModifiers` ignores Cmd/Ctrl/Option but **not Shift**. When you press Shift+Cmd+] on a US keyboard, the event's character is `}`, not `]`.

**Convention**: write the character Cocoa actually produces. So for tab cycling:

- ✅ `shift+cmd+}` — matches Shift+Cmd+] on US layout
- ❌ `shift+cmd+]` — will not match anything on US layout

This is the simplest, most honest rule. It does mean users coming from VS Code (which writes `shift+cmd+]` because it maintains its own layout-aware translation) need to adjust. On non-US layouts, use whatever character your keyboard produces when Shift is applied.

## Available Key Names

**Named keys** (34 total) — case-insensitive:

```
tab  return  escape  space  backspace  delete
up  down  left  right  home  end  pageup  pagedown
f1  f2  f3  f4  f5  f6  f7  f8  f9  f10
f11  f12  f13  f14  f15  f16  f17  f18  f19  f20
```

Note: `backspace` refers to the main ⌫ Delete key (top-right of the alpha block on a Mac keyboard, 0x7F). `delete` refers to the ⌦ Forward Delete key found on full-size keyboards. Each key has exactly one name — no overlap.

**Single-character keys** — any ASCII letter, digit, or punctuation character is written directly in the key position. There's no special escaping needed in TOML basic strings:

```toml
new_window = "cmd+n"           # letter
open_settings = "cmd+,"        # punctuation
custom = "cmd+/"               # another punctuation
```

For the backtick character, write it directly inside a TOML string:

```toml
custom = "cmd+`"               # literal backtick, no escaping needed
```

## Veil-owned Actions

Each of the following actions can be rebound or disabled independently. The default values match Veil's out-of-the-box behavior.

| Action key                | Default shortcut     | Description                                     |
| ------------------------- | -------------------- | ----------------------------------------------- |
| `new_window`              | `cmd+n`              | Open a new Veil window                          |
| `new_window_with_profile` | `cmd+shift+n`        | Open a new window with an NVIM_APPNAME picker   |
| `close_tab`               | `cmd+w`              | Close the current tab (or window if only one)  |
| `close_window`            | `cmd+shift+w`        | Close the entire window                         |
| `quit`                    | `cmd+q`              | Quit Veil                                       |
| `hide`                    | `cmd+h`              | Hide Veil (standard macOS)                      |
| `minimize`                | `cmd+m`              | Minimize the current window                     |
| `toggle_fullscreen`       | `cmd+ctrl+f`         | Toggle full screen                              |
| `open_settings`           | `cmd+,`              | Open `veil.toml` for editing                    |
| `connect_remote`          | `cmd+ctrl+shift+n`   | Connect to a remote nvim instance over TCP      |

**Example:**

```toml
[keys]
# Move new-window to Cmd+Alt+N so Cmd+N can be mapped in nvim
new_window = "cmd+alt+n"

# Disable the Quit shortcut entirely (still reachable from the Veil menu)
quit = ""
```

**Precedence note**: When `bind_default_keymaps = true`, the default Vim keymap dispatch table runs **before** menu delegation in `performKeyEquivalent`. So rebinding a Veil-owned action to one of the default vim keymap shortcuts (`cmd+1` through `cmd+9`, `ctrl+tab`, `shift+ctrl+tab`, `shift+cmd+{`, `shift+cmd+}`) will be silently shadowed by the default keymap. If you want to rebind to these keys, disable the default vim keymaps first with `bind_default_keymaps = false`.

**Not currently configurable**: `Cmd+\`` (cycle between Veil windows) is handled by macOS's built-in Window menu cycling. Rebinding it is out of scope for now.

## Default Vim Keymaps

These are the shortcuts Veil binds by default as a convenience for macOS users. Toggle the entire set on/off with `bind_default_keymaps`:

```toml
[keys]
bind_default_keymaps = false  # default is true
```

When `bind_default_keymaps = false`, each shortcut below is released: the corresponding menu item's keyboard shortcut is cleared, and pressing the key sends it to Neovim as the Vim notation in the "As sent to nvim" column. You can then map it yourself in your nvim config.

| Shortcut          | Default action (nvim command) | As sent to nvim when disabled |
| ----------------- | ----------------------------- | ----------------------------- |
| `cmd+s`           | `:w`                          | `<D-s>`                       |
| `cmd+z`           | `u`                           | `<D-z>`                       |
| `cmd+shift+z`     | `<C-r>`                       | `<S-D-z>`                     |
| `cmd+c`           | `"+y`                         | `<D-c>`                       |
| `cmd+x`           | `"+d`                         | `<D-x>`                       |
| `cmd+v`           | `nvim_paste` RPC              | `<D-v>`                       |
| `cmd+a`           | `ggVG`                        | `<D-a>`                       |
| `cmd+1` … `cmd+8` | `:tabnext N`                  | `<D-1>` … `<D-8>`             |
| `cmd+9`           | `:tablast`                    | `<D-9>`                       |
| `ctrl+tab`        | `:tabnext`                    | `<C-Tab>`                     |
| `shift+ctrl+tab`  | `:tabprevious`                | `<C-S-Tab>`                   |
| `shift+cmd+}`     | `:tabnext`                    | `<S-D-}>`                     |
| `shift+cmd+{`     | `:tabprevious`                | `<S-D-{>`                     |

### About Vim's `<D->` Notation

In Vim (and thus Neovim), the `<D-...>` notation represents the Command key modifier on macOS (`D` for "Duh-command", to disambiguate from `C` which is Ctrl). `<D-s>` means Cmd+S, `<S-D-z>` means Shift+Cmd+Z. Veil uses `KeyUtils.nvimKey` to produce these strings in the canonical `C-S-M-D` modifier order.

## Migration Cheatsheet

If you set `bind_default_keymaps = false`, paste this into your nvim config (`init.lua` or wherever) to recreate Veil's defaults yourself:

```lua
-- Veil default keymaps, re-implemented for bind_default_keymaps = false
vim.keymap.set('n', '<D-s>', ':w<CR>')
vim.keymap.set('n', '<D-z>', 'u')
vim.keymap.set('n', '<S-D-z>', '<C-r>')
vim.keymap.set({'n', 'v'}, '<D-c>', '"+y')
vim.keymap.set({'n', 'v'}, '<D-x>', '"+d')
vim.keymap.set({'n', 'i'}, '<D-v>', '"+p')
vim.keymap.set('n', '<D-a>', 'ggVG')
for i = 1, 8 do
  vim.keymap.set('n', '<D-' .. i .. '>', i .. 'gt')
end
vim.keymap.set('n', '<D-9>', ':tablast<CR>')
vim.keymap.set('n', '<C-Tab>', 'gt')
vim.keymap.set('n', '<C-S-Tab>', 'gT')
vim.keymap.set('n', '<S-D-}>', 'gt')  -- Shift+Cmd+]
vim.keymap.set('n', '<S-D-{>', 'gT')  -- Shift+Cmd+[
```

**Caveat for Cmd+V**: Veil's default Cmd+V uses Neovim's `nvim_paste` RPC, which handles multi-line bracketed paste correctly (important for pasting code into insert mode without auto-indent mangling it). The simple `"+p` mapping above does not fully replicate this behavior. If you rely on multi-line paste from the system clipboard, you may want to either keep `bind_default_keymaps = true`, or write a more sophisticated Lua mapping that calls `vim.paste` or equivalent.
