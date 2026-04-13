# Configurable Keybindings

**Date**: 2026-04-13
**Status**: Approved

## Problem

Veil's keyboard shortcuts are hardcoded in three separate places:

1. Cocoa's default menu key equivalents (File/Edit/View/App/Window menus)
2. Manual additions in `AppDelegate.swift` (connect-remote, profile picker)
3. Runtime dispatch in `NvimView.performKeyEquivalent` (Cmd+1-9, Ctrl+Tab, Shift+Cmd+[/])

Two user-facing issues follow from this:

- The README markets "full key passthrough" as a differentiator, but the keyboard shortcut table lists a dozen intercepted keys. Readers notice the contradiction.
- Vim users who want to define their own `<D-s>`-style mappings in nvim cannot — Veil intercepts these keys unconditionally and forwards them to hardcoded nvim commands.

## Goals

- Let users rebind any Veil-owned action (window management, menu actions, Veil-specific workflows) to a different shortcut or disable its shortcut entirely.
- Let users disable Veil's built-in Vim-friendly convenience mappings (Cmd+S → `:w`, Cmd+1-9 → `:tabnext`, etc.) as a single switch, so those keys pass through to nvim as `<D-s>`, `<D-1>`, etc.
- Keep existing users' behavior unchanged on upgrade unless they opt in.
- Stay consistent with Veil's toml-only, Vim-user-focused configuration philosophy. No Settings UI.

## Non-Goals (v1)

- Settings UI of any kind
- Shortcut conflict detection
- Live config reload (restart Veil, same as all other config)
- Chord / two-stage shortcuts like `Ctrl+K Ctrl+C`
- Rebinding `cycle_window` (Cmd+\`) — stays as macOS system behavior via fall-through. Revisit in v2 if implementation complexity is low.
- User-defined actions beyond the built-in Veil-owned catalog (would require a different design where users specify arbitrary nvim commands)

## Core Concept: Two Categories of Keys

The design hinges on splitting all of Veil's current keyboard shortcuts into exactly two categories, with different configuration semantics.

### Category 1: Veil-owned Actions

Actions that require Veil's native GUI code to execute (NSWindow operations, Veil-specific workflows, menu items). The **action itself** always belongs to Veil — it cannot be delegated to nvim. What users can configure is the **shortcut** bound to it: a different key combination, or an empty string (disabled shortcut, but the menu item stays visible and clickable).

| Action key                 | Default shortcut       | Source                                                |
| -------------------------- | ---------------------- | ----------------------------------------------------- |
| `new_window`               | `cmd+n`                | File menu (Cocoa default)                             |
| `new_window_with_profile`  | `cmd+shift+n`          | File menu (added in AppDelegate)                      |
| `close_tab`                | `cmd+w`                | File menu → `closeTabOrWindow:`                       |
| `close_window`             | `cmd+shift+w`          | File menu → `closeWindow:`                            |
| `quit`                     | `cmd+q`                | App menu (system)                                     |
| `minimize`                 | `cmd+m`                | Window menu (system)                                  |
| `hide`                     | `cmd+h`                | App menu (system)                                     |
| `toggle_fullscreen`        | `cmd+ctrl+f`           | View menu (system)                                    |
| `open_settings`            | `cmd+,`                | App menu                                              |
| `connect_remote`           | `cmd+ctrl+shift+n`     | File menu (added in AppDelegate)                      |

**Excluded**: `cycle_window` (Cmd+\`) stays out of the catalog in v1. It is currently handled by macOS's built-in Window menu cycling via fall-through, not by Veil code. Making it configurable would require Veil to intercept and re-implement the cycling logic. Out of scope for this iteration.

### Category 2: Default Vim Keymaps

Convenience mappings where Veil intercepts a standard macOS shortcut and forwards it to a nvim command. These are Veil doing a favor to users who expect Mac-standard behavior in an editor. A single boolean `bind_default_keymaps` (default `true`) toggles the entire set.

When `bind_default_keymaps = false`, Veil stops binding these shortcuts. Each key then passes through to nvim as a normal key event — `Cmd+S` becomes `<D-s>`, `Ctrl+Tab` becomes `<C-Tab>`, and so on. Users are expected to define their own mappings in their nvim config if they want these keys to do anything. A ready-to-copy Lua migration snippet is provided in the documentation.

The default keymap set splits into two sub-groups based on which Cocoa mechanism currently handles them. This distinction matters for implementation (see Architecture section below):

**Menu-handled** (Edit menu key equivalents):

| Shortcut         | Action (nvim command) | Menu item selector    |
| ---------------- | --------------------- | --------------------- |
| `cmd+s`          | `:w`                  | `saveDocument:`       |
| `cmd+z`          | `u`                   | `undo:`               |
| `cmd+shift+z`    | `<C-r>`               | `redo:`               |
| `cmd+c`          | `"+y`                 | `copy:`               |
| `cmd+x`          | `"+d`                 | `cut:`                |
| `cmd+v`          | `nvim_paste` RPC      | `paste:`              |
| `cmd+a`          | `ggVG`                | `selectAll:`          |

**performKeyEquivalent-handled** (runtime dispatch in NvimView):

| Shortcut                  | Action                |
| ------------------------- | --------------------- |
| `cmd+1` through `cmd+8`   | `:tabnext N`          |
| `cmd+9`                   | `:tablast`            |
| `ctrl+tab`                | `:tabnext`            |
| `shift+ctrl+tab`          | `:tabprevious`        |
| `shift+cmd+]`             | `:tabnext`            |
| `shift+cmd+[`             | `:tabprevious`        |

## Configuration Schema

New `[keys]` section in `veil.toml`:

```toml
[keys]
bind_default_keymaps = true   # Default. See "Default Vim Keymaps" section.

# Rebind Veil's GUI actions. Set to "" to disable a shortcut.
# Menu items remain visible and clickable when their shortcut is disabled.
new_window              = "cmd+n"
new_window_with_profile = "cmd+shift+n"
close_tab               = "cmd+w"
close_window            = "cmd+shift+w"
quit                    = "cmd+q"
minimize                = "cmd+m"
hide                    = "cmd+h"
toggle_fullscreen       = "cmd+ctrl+f"
open_settings           = "cmd+,"
connect_remote          = "cmd+ctrl+shift+n"
```

**Naming rationale**:

- `bind_default_keymaps` is a positive boolean. Earlier candidates like `disable_default_keymaps` and `nobind_default_keymaps` led to double-negative configs (`disable_default_keymaps = true` reads as "yes, don't bind"). Positive naming reads naturally in both states: `true` → Veil binds, `false` → Veil doesn't.
- snake_case matches Veil's existing config fields (`line_height`, `native_tabs`, `update_check`).
- Empty string means "disabled", not `false`. Keeping the field type uniform (always a string) avoids TOML type-union parsing complexity.

**Decoding strategy**:

- New `KeysConfig: Decodable` struct, follows existing `DecodableDefault.Wrapper` pattern for `bind_default_keymaps`
- Per-action fields are `String?`; missing fields fall back to built-in defaults stored in a static dictionary keyed by `KeyAction` enum
- Default-value resolution is done by `KeysConfig.shortcut(for action: KeyAction) -> ShortcutSpec?`: returns user value if set, falls back to built-in default, parses to `ShortcutSpec`, returns `nil` if the resolved string is empty (disabled)
- `VeilConfig` gains a `keys: KeysConfig?` field with a computed accessor that returns a default-constructed `KeysConfig` when nil

## Shortcut String Format

Electron / VS Code style, e.g., `cmd+shift+n`. Chosen over alternatives (Vim's `<C-S-n>`, Cocoa's programmatic struct) because it's the format most macOS developers recognize, is pure ASCII, and is friendly to TOML strings.

**Syntax**:

- Tokens separated by `+`
- Case-insensitive
- Whitespace around `+` tolerated (`cmd + shift + n` parses the same as `cmd+shift+n`)
- Exactly one non-modifier "key" per shortcut (no chord support)

**Modifiers**: `cmd`, `ctrl`, `shift`, `alt` (with `option` as an alias for `alt`).

**Named keys** (~35 entries): special keys that cannot be expressed as a single character. These are the names the parser accepts in the key position:

```
tab, return, escape, space, backspace, delete,
up, down, left, right, home, end, pageup, pagedown,
f1, f2, f3, f4, f5, f6, f7, f8, f9, f10,
f11, f12, f13, f14, f15, f16, f17, f18, f19, f20,
backtick
```

`backtick` is provided as an alias for the `` ` `` character because escaping a literal backtick inside a TOML string inside a parsed keybinding can be ambiguous.

**Single-character keys**: any letter, digit, or punctuation character (`a`, `1`, `,`, `/`, `[`, `;`, etc.) is written directly in the key position. These do not need an entry in the named key table — the parser falls back to treating any remaining token as a single-character key.

## Parser and Runtime Matching

New file `Veil/Keybindings/ShortcutSpec.swift`.

### Data types

```swift
struct ShortcutSpec: Equatable {
    let modifiers: NSEvent.ModifierFlags
    let key: Key
}

enum Key: Equatable {
    case character(String)   // Matched via charactersIgnoringModifiers
    case named(NamedKey)     // Matched via specialKey or keyCode
}

enum NamedKey {
    case tab, `return`, escape, space, backspace, delete
    case up, down, left, right, home, end, pageUp, pageDown
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20
    case backtick
}
```

### Parse

```swift
static func parse(_ string: String) -> ShortcutSpec?
```

Algorithm:

1. Return `nil` for empty string (caller interprets as "disabled")
2. Split by `+`, trim whitespace on each token, lowercase
3. Classify each token: modifier name → add to modifier flags; otherwise treat as candidate key
4. Exactly one non-modifier token is required; zero or multiple → return `nil`
5. Resolve the key: look up in the named key table first; fall back to single-character if unknown
6. Reject multi-character keys that aren't in the named table → return `nil`

### Runtime matching

```swift
func matches(_ event: NSEvent) -> Bool
```

1. Compare `event.modifierFlags.intersection(.deviceIndependentFlagsMask)` with `self.modifiers`
2. For `.character(c)`: compare with `event.charactersIgnoringModifiers?.lowercased() == c`
3. For `.named(key)`: look up `(NSEvent.SpecialKey?, keyCode?)` for the named key and match against the event

**Character-based matching (not keycode-based)** is chosen deliberately, matching Vim's and VS Code's default behavior. Users who write `cmd+/` in any keyboard layout will match whenever the user types something that produces `/`, regardless of the physical key position. This is the dominant convention in cross-platform editors and what users expect.

### Menu key equivalent conversion

```swift
func toMenuKeyEquivalent() -> (String, NSEvent.ModifierFlags)?
```

NSMenu uses `keyEquivalent: String` + `keyEquivalentModifierMask: NSEvent.ModifierFlags`. The conversion handles Cocoa's quirk where `Shift+Letter` shortcuts use the uppercase letter in `keyEquivalent` and still include `.shift` in the mask (this convention is already visible in `AppDelegate.swift`'s existing manual menu items).

Returns `nil` for named keys that cannot be expressed as menu key equivalents or for inputs the converter doesn't support.

## Architecture: Single Source of Truth + Two Consumers

The core architectural insight: `VeilConfig.current.keys` becomes the **single source of truth** for all shortcut bindings. It is consumed in two places, which must stay consistent.

### Key event routing in Cocoa

Understanding Cocoa's key event flow is essential for this design. When a key is pressed:

1. NSApplication first asks the menu bar to handle it via `performKeyEquivalent:`. Any menu item with a matching key equivalent captures the event and its action selector is invoked.
2. If no menu item matches, the event goes to the key view's `performKeyEquivalent:` (in Veil: `NvimView.performKeyEquivalent`) and walks up the responder chain.
3. If still nothing handles it, the event becomes a regular `keyDown:`.

**Implication**: `NvimView.performKeyEquivalent` is a second-chance mechanism. It only ever sees shortcuts not claimed by menu items. This shapes the two-consumer design below.

### Consumer 1: AppDelegate menu construction

Menus are built the same way they are today (Cocoa's default menu + manual additions in `AppDelegate.swift`). A new **post-construction pass** walks the relevant menu items and sets each one's `keyEquivalent` / `keyEquivalentModifierMask` from the config:

- For each Veil-owned action, locate the corresponding menu item by its action selector (e.g., `#selector(NSDocumentController.newDocument(_:))` for `new_window`), then apply the config-derived shortcut.
- If an action's shortcut is `""` (disabled): clear `keyEquivalent` on its menu item. Item stays visible and clickable; no shortcut.
- If `bind_default_keymaps == false`: additionally clear `keyEquivalent` on all Edit menu items whose selectors match the menu-handled default vim keymap set (`saveDocument:`, `undo:`, `redo:`, `cut:`, `copy:`, `paste:`, `selectAll:`).

A helper `findMenuItem(selector:)` walks the main menu tree to locate items. A helper `applyShortcut(to:action:)` applies a config-derived `ShortcutSpec` to a given menu item.

**Key invariant**: what a menu displays as its shortcut is always what actually triggers the action. If `new_window` is rebound to `cmd+alt+n`, the File menu's "New Window" item must display `⌥⌘N`.

### Consumer 2: NvimView.performKeyEquivalent

Rewritten to be config-driven, handling only the non-menu default vim keymaps (`Cmd+1-9`, `Ctrl+Tab`, `Shift+Ctrl+Tab`, `Shift+Cmd+[/]`):

1. Build a list of `(ShortcutSpec, DefaultKeymapAction)` pairs at startup from the default keymap table (a Swift data structure, not config-driven since these defaults are hardcoded by Veil — users only get to disable them collectively, not rebind them individually).
2. On each `performKeyEquivalent` call:
   - If `bind_default_keymaps == false`, return `super.performKeyEquivalent(with: event)` immediately. The key then falls through to `keyDown` and is sent to nvim as `<D-1>`, `<C-Tab>`, etc.
   - Otherwise, iterate the list and match each spec against the event. On match, dispatch to the corresponding action and return `true`.
   - No match → return `super.performKeyEquivalent(with: event)`.
3. The existing `systemKeys` whitelist is removed. Menu items now naturally fall through via Cocoa's responder chain without needing an allow-list.

`DefaultKeymapAction` is a small internal type that holds the action to execute. It needs to support both "run a fixed nvim command string" and "compute a command from the matched shortcut" (Cmd+1 through Cmd+8 each maps to a different `:tabnext N` command).

### How `bind_default_keymaps = false` Works

Both consumers respond to this single switch. When `false`:

- **AppDelegate pass** clears key equivalents on the seven menu-handled Edit menu items. Pressing Cmd+S is no longer captured by the menu bar.
- **performKeyEquivalent** skips all matching. Pressing Cmd+1, Ctrl+Tab, etc. no longer triggers Veil's dispatch.
- Both paths let the event fall through to the eventual `keyDown:` handler, which sends the key to nvim as `<D-s>`, `<D-1>`, `<C-Tab>`, and so on (via Veil's existing `KeyUtils.nvimKey` path).

The two consumers must be kept synchronized — disabling only one of them would leave either the menu or performKeyEquivalent still intercepting part of the set, breaking the "keys pass through to nvim" promise.

## Files Changed

- `Veil/Config.swift` — new `KeysConfig` struct, `KeyAction` enum, static default keymap table, `keys` field on `VeilConfig`, `shortcut(for:)` accessor.
- `Veil/Keybindings/ShortcutSpec.swift` — **new file**. Data types + parser + runtime matching + menu conversion + named key lookup table.
- `Veil/AppDelegate.swift` — post-construction pass that applies config-driven key equivalents to menu items. Replaces hardcoded `keyEquivalent` strings in manually-added menu items with config lookups.
- `Veil/Rendering/NvimView+Keyboard.swift` — `performKeyEquivalent` rewritten as config-driven dispatch over the default keymap list. Remove `systemKeys` whitelist.
- `veil.sample.toml` — new `[keys]` section as commented-out example.
- `KEYBOARD.md` — **new file** at project root. Six sections: Overview, Shortcut string format, Available key names, Veil-owned actions table, Default Vim keymaps table, Migration cheatsheet.
- `README.md` — simplify Keyboard section (remove long shortcut table, point to KEYBOARD.md). Rewrite the "Full key passthrough" feature line to accurately describe the passthrough behavior.

## KEYBOARD.md Outline

1. **Overview** — The two-category philosophy. Why Veil treats Vim users as owners of their own keymap.
2. **Shortcut string format** — Full grammar with examples.
3. **Available key names** — Complete modifier list, complete named key list (35 entries), note on single-character keys.
4. **Veil-owned actions** — Table with action key, default shortcut, description. Note that `""` disables a shortcut while keeping the menu item accessible. Note that `cycle_window` (Cmd+\`) is currently fixed.
5. **Default Vim keymaps** — Table listing each shortcut, the nvim command it triggers by default, and the equivalent notation (`<D-s>`, `<C-Tab>`) the key is sent to nvim as when `bind_default_keymaps = false`. Brief explanation of Vim's `<D->` notation for macOS Cmd.
6. **Migration cheatsheet** — Ready-to-copy Lua snippet:

```lua
-- Veil default keymaps, re-implemented for bind_default_keymaps = false
vim.keymap.set('n', '<D-s>', ':w<CR>')
vim.keymap.set('n', '<D-z>', 'u')
vim.keymap.set('n', '<D-S-z>', '<C-r>')
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
vim.keymap.set('n', '<D-}>', 'gt')  -- Shift+Cmd+]
vim.keymap.set('n', '<D-{>', 'gT')  -- Shift+Cmd+[
```

**Caveat for Cmd+V**: Veil's default uses `nvim_paste` RPC which handles multi-line bracketed paste correctly. A simple `"+p` mapping doesn't fully replicate this for insert mode with multi-line content. Users who care about this behavior should either keep `bind_default_keymaps = true` or write a more sophisticated Lua mapping. This caveat is documented in the cheatsheet section.

## Implementation Order (for the eventual plan)

1. `ShortcutSpec` + parser + named key table + unit tests. Self-contained, no dependencies on Veil internals.
2. `KeysConfig` + `KeyAction` + default value table + `VeilConfig` integration.
3. `NvimView.performKeyEquivalent` rewrite. Tests existing behavior unchanged; tests `bind_default_keymaps = false` makes keys fall through.
4. `AppDelegate` menu construction pass. Most complex and touches the most code — do last, after all pieces are in place.
5. `veil.sample.toml`, `KEYBOARD.md`, `README.md` — documentation.

## Verification

- Unit tests for `ShortcutSpec.parse` covering all modifier combinations, all named keys, single-character keys, malformed input, empty string.
- Unit tests for `ShortcutSpec.matches` against synthetic `NSEvent` instances.
- Manual verification that existing users' behavior is unchanged with no config file or with empty `[keys]` section.
- Manual verification of the `bind_default_keymaps = false` flow end-to-end: pressing Cmd+S, Cmd+1, Ctrl+Tab all reach nvim as `<D-s>`, `<D-1>`, `<C-Tab>`.
- Manual verification of rebinding: change `new_window = "cmd+alt+n"`, confirm the File menu displays `⌥⌘N` and pressing it opens a new window.
- Manual verification of disabling a Veil-owned action: set `quit = ""`, confirm the App menu's Quit item has no shortcut but is still clickable.
