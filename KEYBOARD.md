# Keyboard Configuration

Veil reads keyboard configuration from `~/.config/veil/veil.toml`. Changes apply to windows opened after the file is saved.

## Contents

- [App shortcuts and Neovim keymaps](#app-shortcuts-and-neovim-keymaps)
- [Customizing app shortcuts](#customizing-app-shortcuts)
- [Customizing Neovim keymaps](#customizing-neovim-keymaps)
- [Shortcut syntax](#shortcut-syntax)

## App shortcuts and Neovim keymaps

Veil's keybindings split into two categories that differ in ownership and configuration.

**App shortcuts** trigger Veil's own actions: open a new window, quit, hide Veil, open settings, connect to a remote nvim. They correspond to items in Veil's menu bar. Each shortcut can be rebound or disabled independently. Disabling a shortcut leaves the menu item visible and clickable; only the keybinding is removed.

**Neovim keymaps** are macOS-style shortcuts that Veil pre-binds to Neovim commands so the editor behaves like a native Mac app by default. `cmd+s` runs `:w`, `cmd+z` runs `u`, `cmd+1` through `cmd+9` switch tabs. They form a single all-or-nothing set, controlled by `bind_default_keymaps`: when `true` (the default), every key is bound to its Neovim action; when `false`, every key passes through to Neovim verbatim (`<D-s>`, `<D-z>`, `<D-1>`, ...) for you to map in your nvim config.

Veil ships sensible defaults in both categories so it works well without any configuration. The two sections below cover how to change either.

## Customizing app shortcuts

Every app shortcut has a config key under `[keyboard]`. Assign a shortcut string to rebind, or `""` to disable.

```toml
[keyboard]
# Rebind: move new-window from Cmd+N to Cmd+Alt+N (so Cmd+N is free for nvim)
new_window = "cmd+alt+n"

# Disable: Quit is still reachable from the Veil menu
quit = ""
```

Full list of app shortcuts:

| Config key                | Default            | Action                                        |
| ------------------------- | ------------------ | --------------------------------------------- |
| `new_window`              | `cmd+n`            | Open a new Veil window                        |
| `new_window_with_profile` | `cmd+shift+n`      | Open a new window with `NVIM_APPNAME` picker  |
| `close_tab`               | `cmd+w`            | Close the current tab (or window if only one) |
| `close_window`            | `cmd+shift+w`      | Close the entire window                       |
| `quit`                    | `cmd+q`            | Quit Veil                                     |
| `hide`                    | `cmd+h`            | Hide Veil                                     |
| `minimize`                | `cmd+m`            | Minimize the current window                   |
| `toggle_fullscreen`       | `cmd+ctrl+f`       | Toggle full screen                            |
| `open_settings`           | `cmd+,`            | Open `veil.toml` for editing                  |
| `connect_remote`          | `cmd+ctrl+shift+n` | Connect to a remote nvim instance over TCP    |

**Conflict with Neovim keymaps**: when `bind_default_keymaps = true` (the default), every key listed in [Customizing Neovim keymaps](#customizing-neovim-keymaps) is claimed by Veil. Rebinding an app shortcut to one of those keys is silently shadowed. Either pick a different key or set `bind_default_keymaps = false` to free the entire set.

**Not configurable**: `Cmd+backtick` (window cycling) is handled by macOS's built-in Window menu, not by Veil.

## Customizing Neovim keymaps

The full set of macOS shortcuts Veil pre-binds to Neovim:

| Shortcut           | Default Neovim command | Sent to nvim when disabled |
| ------------------ | ---------------------- | -------------------------- |
| `cmd+s`            | `:w`                   | `<D-s>`                    |
| `cmd+z`            | `u`                    | `<D-z>`                    |
| `cmd+shift+z`      | `<C-r>`                | `<S-D-z>`                  |
| `cmd+c`            | `"+y`                  | `<D-c>`                    |
| `cmd+x`            | `"+d`                  | `<D-x>`                    |
| `cmd+v`            | `nvim_paste` RPC       | `<D-v>`                    |
| `cmd+a`            | `ggVG`                 | `<D-a>`                    |
| `cmd+1` to `cmd+8` | `:tabnext N`           | `<D-1>` to `<D-8>`         |
| `cmd+9`            | `:tablast`             | `<D-9>`                    |
| `ctrl+tab`         | `:tabnext`             | `<C-Tab>`                  |
| `shift+ctrl+tab`   | `:tabprevious`         | `<C-S-Tab>`                |
| `shift+cmd+]`      | `:tabnext`             | `<S-D-}>`                  |
| `shift+cmd+[`      | `:tabprevious`         | `<S-D-{>`                  |

The "Sent to nvim" column uses Vim's notation for modifier-prefixed keys: `C` is Ctrl, `S` is Shift, `M` is Alt, `D` is Cmd, written in the canonical `C-S-M-D` order. So `<D-s>` is `cmd+s` and `<S-D-z>` is `shift+cmd+z`.

To override Veil's defaults entirely, disable them:

```toml
[keyboard]
bind_default_keymaps = false
```

Veil then forwards every key in the table to Neovim as the notation in the rightmost column. Map them in your nvim config:

```lua
-- Veil default keymaps, re-implemented for bind_default_keymaps = false
vim.keymap.set('n', '<D-s>', ':w<CR>')
vim.keymap.set('n', '<D-z>', 'u')
vim.keymap.set('n', '<S-D-z>', '<C-r>')
vim.keymap.set({'n', 'v'}, '<D-c>', '"+y')
vim.keymap.set({'n', 'v'}, '<D-x>', '"+d')
vim.keymap.set({'n', 'i', 'c', 't'}, '<D-v>', function()
  vim.paste(vim.split(vim.fn.getreg('+'), '\n', { plain = true }), -1)
end)
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

There is no per-key disable. The toggle is intentionally all-or-nothing because the value of these keymaps lies in their consistency: a partially-bound set creates more confusion than either extreme.

**Caveat for `cmd+v`**: the Lua mapping above calls `vim.paste`, the same API Veil uses internally. Veil's version is still more reliable and faster because it reads the system clipboard directly instead of going through Neovim's clipboard provider. If you paste a lot of multi-line content, keeping `bind_default_keymaps = true` is the safer choice.

## Shortcut syntax

A shortcut is one or more modifiers followed by exactly one key, joined by `+`:

```
cmd+shift+n
ctrl+tab
shift+cmd+]
```

Rules:

- Modifier names and named keys are case-insensitive (`CMD+Tab` and `cmd+tab` are equivalent).
- Whitespace around `+` is tolerated (`cmd + shift + n` parses the same as `cmd+shift+n`).
- Exactly one non-modifier key per shortcut. Chord shortcuts such as `Ctrl+K Ctrl+C` are not supported.
- An empty string (`""`) means "disabled".
- For shifted punctuation, you can write either the unshifted character (`shift+cmd+]`) or the shifted one (`shift+cmd+}`); both match the same physical keystroke.

Modifiers:

| Name     | Meaning         |
| -------- | --------------- |
| `cmd`    | ⌘ Command       |
| `ctrl`   | ⌃ Control       |
| `shift`  | ⇧ Shift         |
| `alt`    | ⌥ Option        |
| `option` | alias for `alt` |

**Single-character keys**: any ASCII letter, digit, or punctuation, written directly. No escaping needed in TOML basic strings.

```toml
new_window    = "cmd+n"
open_settings = "cmd+,"
custom        = "cmd+`"
```

**Named keys** (case-insensitive):

| Category   | Keys                                                          |
| ---------- | ------------------------------------------------------------- |
| Editing    | `tab` `return` `escape` `space` `backspace` `delete` `insert` |
| Arrows     | `up` `down` `left` `right`                                    |
| Navigation | `home` `end` `pageup` `pagedown`                              |
| Function   | `f1` through `f35`                                            |

`backspace` is the main ⌫ Delete key (top-right of the alpha block, produces `0x7F`). `delete` is the ⌦ Forward Delete key found on full-size keyboards.
