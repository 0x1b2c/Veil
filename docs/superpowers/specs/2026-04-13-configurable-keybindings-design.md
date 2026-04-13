# Configurable Keybindings

**Date**: 2026-04-13
**Status**: Approved

## Problem

Veil's keyboard shortcuts are hardcoded in three separate places:

1. `Veil/Base.lproj/MainMenu.xib` — the main menu structure with key equivalents (Cmd+N, Cmd+S, Cmd+W, Cmd+Z, Cmd+C/X/V/A, Cmd+M, Cmd+Q, Cmd+H, Cmd+,, Cmd+Ctrl+F)
2. `Veil/AppDelegate.swift` — two manually added menu items (`connect_remote` as Cmd+Ctrl+Shift+N, `new_window_with_profile` as Cmd+Shift+N)
3. `Veil/Rendering/NvimView+Keyboard.swift` — runtime dispatch in `performKeyEquivalent` for Cmd+1-9, Ctrl+Tab / Shift+Ctrl+Tab, Shift+Cmd+[/] (actually `{`/`}`, see "Shifted Punctuation" section)

Two user-facing problems follow:

- The README markets "full key passthrough" as a differentiator, but the keyboard shortcut table lists a dozen intercepted keys. Readers notice the contradiction.
- Vim users who want to define their own `<D-s>`-style mappings in nvim cannot — Veil intercepts these keys unconditionally and forwards them to hardcoded nvim commands.

## Goals

- Let users rebind any Veil-owned action (window management, menu actions, Veil-specific workflows) to a different shortcut or disable its shortcut entirely.
- Let users disable Veil's built-in Vim-friendly convenience mappings (Cmd+S → `:w`, Cmd+1-9 → `:tabnext`, etc.) as a single switch, so those keys pass through to nvim as `<D-s>`, `<D-1>`, etc.
- Keep existing users' behavior unchanged on upgrade unless they opt in.
- Stay consistent with Veil's toml-only, Vim-user-focused configuration philosophy. No Settings UI.

## Non-Goals (v1)

- Settings UI of any kind
- Shortcut conflict detection (user's responsibility; last-write-wins is undefined and that's okay)
- Live config reload (restart Veil, same as all other config)
- Chord / two-stage shortcuts like `Ctrl+K Ctrl+C`
- Rebinding `cycle_window` (Cmd+\`) — stays as macOS system behavior via fall-through. Revisit in v2 if implementation complexity is low.
- User-defined actions beyond the built-in Veil-owned catalog (would require a different design where users specify arbitrary nvim commands)
- Layout-aware matching for shifted punctuation (users write the character Cocoa actually produces; see "Shifted Punctuation" section)

## Ground Truth: Current Menu Structure

All key equivalents come from `Veil/Base.lproj/MainMenu.xib` except the two manually added in `AppDelegate.swift`. Verified selectors:

| Action key                 | Current menu   | Selector                            | Defined in             |
| -------------------------- | -------------- | ----------------------------------- | ---------------------- |
| `new_window`               | File           | `newDocument:`                      | MainMenu.xib           |
| `new_window_with_profile`  | File           | `newDocumentWithProfilePicker:`     | AppDelegate (inserted) |
| `close_tab`                | File           | `closeTabOrWindow:`                 | MainMenu.xib           |
| `close_window`             | File           | `closeWindow:`                      | MainMenu.xib           |
| `save`                     | File           | `saveDocument:`                     | MainMenu.xib           |
| `quit`                     | Veil (App)     | `terminate:`                        | MainMenu.xib           |
| `hide`                     | Veil (App)     | `hide:`                             | MainMenu.xib           |
| `minimize`                 | Window         | `performMiniaturize:`               | MainMenu.xib           |
| `toggle_fullscreen`        | View           | `toggleFullScreen:`                 | MainMenu.xib           |
| `open_settings`            | Veil (App)     | `openSettings:`                     | MainMenu.xib           |
| `connect_remote`           | File           | `connectToRemote:`                  | AppDelegate (inserted) |
| `undo`                     | Edit           | `undo:`                             | MainMenu.xib           |
| `redo`                     | Edit           | `redo:`                             | MainMenu.xib           |
| `cut`                      | Edit           | `cut:`                              | MainMenu.xib           |
| `copy`                     | Edit           | `copy:`                             | MainMenu.xib           |
| `paste`                    | Edit           | `paste:`                            | MainMenu.xib           |
| `select_all`               | Edit           | `selectAll:`                        | MainMenu.xib           |

Important: `saveDocument:` is a **File menu** item in Veil, not Edit — this matters for the "clear key equivalents when `bind_default_keymaps = false`" logic. We scan the **whole main menu tree** by selector, not restricted to any single menu.

## Core Concept: Two Categories of Keys

The design splits all of Veil's current keyboard shortcuts into exactly two categories, with different configuration semantics.

### Category 1: Veil-owned Actions

Actions that require Veil's native GUI code to execute (NSWindow operations, Veil-specific workflows, menu items). The **action itself** always belongs to Veil — it cannot be delegated to nvim. What users can configure is the **shortcut** bound to it: a different key combination, or an empty string (disabled shortcut, but the menu item stays visible and clickable).

| Action key                 | Default shortcut    | Selector                        |
| -------------------------- | ------------------- | ------------------------------- |
| `new_window`               | `cmd+n`             | `newDocument:`                  |
| `new_window_with_profile`  | `cmd+shift+n`       | `newDocumentWithProfilePicker:` |
| `close_tab`                | `cmd+w`             | `closeTabOrWindow:`             |
| `close_window`             | `cmd+shift+w`       | `closeWindow:`                  |
| `quit`                     | `cmd+q`             | `terminate:`                    |
| `hide`                     | `cmd+h`             | `hide:`                         |
| `minimize`                 | `cmd+m`             | `performMiniaturize:`           |
| `toggle_fullscreen`        | `cmd+ctrl+f`        | `toggleFullScreen:`             |
| `open_settings`            | `cmd+,`             | `openSettings:`                 |
| `connect_remote`           | `cmd+ctrl+shift+n`  | `connectToRemote:`              |

**Excluded**: `cycle_window` (Cmd+\`) stays out of the catalog in v1. It is currently handled by macOS's built-in Window menu cycling via fall-through, not by Veil code. Making it configurable would require Veil to intercept and re-implement the cycling logic. Out of scope for this iteration.

### Category 2: Default Vim Keymaps

Convenience mappings where Veil forwards a standard macOS shortcut to an nvim command. A single boolean `bind_default_keymaps` (default `true`) toggles the entire set.

When `bind_default_keymaps = false`, Veil stops binding these shortcuts. Each key then arrives at nvim as a normal key event (`<D-s>`, `<C-Tab>`, etc.). Users are expected to define their own mappings in their nvim config.

The default keymap set splits into two sub-groups based on which mechanism currently handles them. Both sub-groups are affected together by the single `bind_default_keymaps` switch — but the mechanism used to disable each differs, and must be kept in sync.

**Menu-handled** (each shortcut is currently a menu item key equivalent):

| Default shortcut | nvim action         | Selector        | Menu                   |
| ---------------- | ------------------- | --------------- | ---------------------- |
| `cmd+s`          | `:w`                | `saveDocument:` | File (in this project) |
| `cmd+z`          | `u`                 | `undo:`         | Edit                   |
| `cmd+shift+z`    | `<C-r>`             | `redo:`         | Edit                   |
| `cmd+c`          | `"+y`               | `copy:`         | Edit                   |
| `cmd+x`          | `"+d`               | `cut:`          | Edit                   |
| `cmd+v`          | `nvim_paste` RPC    | `paste:`        | Edit                   |
| `cmd+a`          | `ggVG`              | `selectAll:`    | Edit                   |

**performKeyEquivalent-handled** (not owned by any menu item; dispatched at runtime in `NvimView.performKeyEquivalent`):

| Default shortcut (spec string) | nvim action       | Notes                                      |
| ------------------------------ | ----------------- | ------------------------------------------ |
| `cmd+1` through `cmd+8`        | `:tabnext N`      |                                            |
| `cmd+9`                        | `:tablast`        |                                            |
| `ctrl+tab`                     | `:tabnext`        |                                            |
| `shift+ctrl+tab`               | `:tabprevious`    |                                            |
| `shift+cmd+}`                  | `:tabnext`        | Shifted `]`; see "Shifted Punctuation"     |
| `shift+cmd+{`                  | `:tabprevious`    | Shifted `[`; see "Shifted Punctuation"     |

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
hide                    = "cmd+h"
minimize                = "cmd+m"
toggle_fullscreen       = "cmd+ctrl+f"
open_settings           = "cmd+,"
connect_remote          = "cmd+ctrl+shift+n"
```

**Naming rationale**:

- `bind_default_keymaps` is a positive boolean. Earlier candidates like `disable_default_keymaps` led to double-negative configs. Positive naming reads naturally in both states.
- snake_case matches Veil's existing config fields (`line_height`, `native_tabs`, `update_check`).
- Empty string means "disabled". Keeping the field type uniform (always a string) avoids TOML type-union parsing complexity.

### Decoding sketch

```swift
struct KeysConfig: Decodable {
    @DecodableDefault.Wrapper<DecodableDefault.True>
    var bind_default_keymaps: Bool

    // Per-action user values. Nil means "use the built-in default".
    // Empty string means "user explicitly disabled this shortcut".
    var new_window: String?
    var new_window_with_profile: String?
    var close_tab: String?
    var close_window: String?
    var quit: String?
    var hide: String?
    var minimize: String?
    var toggle_fullscreen: String?
    var open_settings: String?
    var connect_remote: String?
}
```

- Built-in per-action defaults are stored in a static dictionary `[KeyAction: String]`, not in property wrappers (defaults differ per field, the wrapper pattern is awkward for that).
- `KeyAction` is an enum with one case per entry in the action catalog.
- `VeilConfig` gains a `keys: KeysConfig?` field. A computed accessor returns a default-constructed `KeysConfig()` when nil, so downstream code can always call `VeilConfig.current.keysOrDefault.shortcut(for: .newWindow)` without nil-checking.
- `KeysConfig.shortcut(for action: KeyAction) -> ShortcutSpec?` resolves the effective string (user value or built-in default), parses to `ShortcutSpec`, and returns `nil` when: the effective string is empty (user-disabled), OR the string fails to parse (malformed). On parse failure, log a warning to stderr and behave as if the user disabled the shortcut. This is intentionally permissive: one broken shortcut does not break the whole config file.

## Shortcut String Format

Electron / VS Code style, e.g., `cmd+shift+n`. Chosen over alternatives (Vim's `<C-S-n>`, Cocoa's programmatic struct) because it's the format most macOS developers recognize, is pure ASCII, and is friendly to TOML strings.

**Syntax**:

- Tokens separated by `+`
- Case-insensitive for modifiers and named keys
- Whitespace around `+` tolerated (`cmd + shift + n` parses the same as `cmd+shift+n`)
- Exactly one non-modifier "key" per shortcut (no chord support)

**Modifiers**: `cmd`, `ctrl`, `shift`, `alt` (with `option` as an alias for `alt`).

**Named keys** (~34 entries): special keys that cannot be expressed as a single character. These are the names the parser accepts in the key position:

```
tab, return, escape, space, backspace, delete,
up, down, left, right, home, end, pageup, pagedown,
f1, f2, f3, f4, f5, f6, f7, f8, f9, f10,
f11, f12, f13, f14, f15, f16, f17, f18, f19, f20
```

No `backtick` alias: TOML basic strings handle a literal `` ` `` without escaping (`"cmd+\`"` is just `"cmd+``"`), and `cycle_window` is out of scope for v1 anyway. Users who need `` ` `` in a shortcut use the single-character fallback below.

**Single-character keys**: any letter, digit, or punctuation character (`a`, `1`, `,`, `/`, `[`, `;`, `` ` ``, etc.) is written directly in the key position. These do not need an entry in the named key table — the parser falls back to treating any remaining single-character token as the key.

### Shifted Punctuation

Cocoa's `NSEvent.charactersIgnoringModifiers` ignores Cmd/Ctrl/Option but **not Shift**. On a US layout, pressing Shift+Cmd+] produces an event with `charactersIgnoringModifiers == "}"`, not `"]"`. This is why the existing code in `NvimView+Keyboard.swift` hardcodes `chars == "{" || chars == "}"` to match Shift+Cmd+[/].

**Convention adopted**: users write the character Cocoa actually produces. For shifted punctuation on US layout, that means the shifted form. So:

- `shift+cmd+]` is **wrong** — it won't match anything on US layout because the event produces `}`, not `]`.
- `shift+cmd+}` is **right** — it matches the event.

This is a deliberate tradeoff:
- **Pro**: simple, honest about the underlying Cocoa behavior, no layout-aware translation table, no magic
- **Con**: diverges from VS Code convention (VS Code writes `shift+cmd+]` because it maintains its own layout-aware translation), may surprise users coming from that ecosystem

This convention is documented clearly in `KEYBOARD.md` with examples. The built-in default keymap table for tab cycling uses `shift+cmd+{` and `shift+cmd+}`, matching the existing hardcoded strings.

## Parser and Runtime Matching

New file `Veil/Keybindings/ShortcutSpec.swift`.

### Data types

```swift
struct ShortcutSpec: Equatable {
    let modifiers: NSEvent.ModifierFlags
    let key: Key
}

enum Key: Equatable {
    case character(String)   // single-char keys, matched via charactersIgnoringModifiers
    case named(NamedKey)     // special keys, matched via NSEvent.SpecialKey / keyCode
}

enum NamedKey {
    case tab, `return`, escape, space, backspace, delete
    case up, down, left, right, home, end, pageUp, pageDown
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20
}
```

### Parse

```swift
static func parse(_ string: String) -> ShortcutSpec?
```

Algorithm:

1. Return `nil` for empty string (caller interprets as "disabled")
2. Split by `+`, trim whitespace on each token
3. Lowercase modifier tokens and named key tokens; single-character keys are kept as-is (case-sensitive — `a` and `A` are not the same, though after shift-normalization they behave the same in practice)
4. Classify each token: modifier name → add to modifier flags; otherwise candidate key
5. Exactly one non-modifier token required; zero or multiple → return `nil`
6. Resolve the key: look up in the named key table first; fall back to single-character if unknown
7. Reject multi-character keys that aren't in the named table → return `nil`

### Runtime matching

```swift
func matches(_ event: NSEvent) -> Bool
```

Modifier comparison uses a **narrower mask** than `.deviceIndependentFlagsMask` because we need to ignore `.function` (which Cocoa automatically adds to F-key events) and `.numericPad` (which Cocoa adds to arrow key events on some keyboards), and because Caps Lock is never part of a shortcut:

```swift
let relevantMask: NSEvent.ModifierFlags =
    [.command, .control, .option, .shift]
let eventMods = event.modifierFlags.intersection(relevantMask)
guard eventMods == self.modifiers else { return false }
```

Then match the key portion:
- For `.character(c)`: `event.charactersIgnoringModifiers?.lowercased() == c.lowercased()` — case-insensitive comparison because users may write `cmd+a` or `cmd+A` and mean the same thing.
- For `.named(key)`: look up `(NSEvent.SpecialKey?, keyCode?)` for the named key and match against the event. Function keys are identified via `NSEvent.SpecialKey.f1` etc. Arrow keys via `NSEvent.SpecialKey.upArrow` etc. Tab/Return/Escape/Space/Backspace via keyCode because they arrive as regular character events not SpecialKey.

The named key lookup table lives alongside the parser in `ShortcutSpec.swift` and maps both directions (parse: name → NamedKey; match: NamedKey → event predicate).

### Menu key equivalent conversion

```swift
func toMenuKeyEquivalent() -> (String, NSEvent.ModifierFlags)?
```

NSMenu uses `keyEquivalent: String` + `keyEquivalentModifierMask: NSEvent.ModifierFlags`. For lowercase letters, digits, and punctuation (including already-shifted punctuation like `}`), the mapping is a direct pass-through: the parsed character becomes `keyEquivalent` verbatim, and the parsed modifiers become the mask.

**Veil's Shift+letter convention**, applied uniformly by `toMenuKeyEquivalent()`: when Shift is set and the key is an ASCII letter, use the **uppercase letter** in `keyEquivalent` and include `.shift` explicitly in `modifierMask`. This is the unambiguous form that works regardless of Cocoa's quirks around interpreting uppercase-in-keyEquivalent. The post-construction menu pass overwrites whatever the xib had with this consistent form.

The uppercase-letter rule applies **only to ASCII letters**. Punctuation passes through verbatim because the user already supplies the shifted glyph (e.g., `cmd+shift+}` becomes `keyEquivalent = "}"` with `modifierMask = [.command, .shift]` — we do NOT try to un-shift `}` back to `]`). Digits and named keys (tab, return, arrows, function keys) also pass through without case transformation.

For named keys, use the appropriate special-character string that NSMenu recognizes (e.g., `tab` maps to `"\t"`, `return` to `"\r"`) and include the parsed modifiers in the mask. Named keys that NSMenu has no standard representation for cause the function to return `nil`, and the caller (Consumer 1) leaves the menu item's shortcut unset.

## Architecture: Single Source of Truth + Two Consumers

`VeilConfig.current.keysOrDefault` is the **single source of truth** for all shortcut bindings. It is consumed in two places, which must stay consistent.

### Key event routing in Cocoa (critical context)

Cocoa's key event flow when a key is pressed (accurate as of macOS 14+):

1. `NSApplication.sendEvent(_:)` receives the event.
2. For key down events with modifiers, NSApplication walks the main menu tree and asks each `NSMenuItem` whether its `keyEquivalent` matches. Any match fires the item's action selector (via the responder chain) and consumes the event.
3. If no menu item matches, the event is delivered to the key window, which calls `performKeyEquivalent(with:)` on the first responder's ancestor chain. This is where `NvimView.performKeyEquivalent` runs.
4. If `performKeyEquivalent` returns `false` (nobody handled it) **and** the event is a plain character key (no Cmd/Ctrl modifiers OR the modifiers are supposed to reach the first responder), the event becomes a regular `keyDown:` dispatched to the first responder.
5. For Cmd+letter events specifically: if step 2 doesn't match any menu item and step 3 returns `false`, the event is **dropped with a system beep**, not re-dispatched to `keyDown:`. This is why the existing `NvimView.performKeyEquivalent` synthesizes the `<D-letter>` send itself in its fall-through branch.

**Implication for this design**: the `bind_default_keymaps = false` path cannot rely on Cmd+letter events "falling through to keyDown". The synthesis to `<D-s>`, `<D-1>`, etc. must happen inside `performKeyEquivalent` itself. This is how the existing code already works (with the `systemKeys` whitelist as its gating mechanism), and the new design preserves this approach.

### Consumer 1: AppDelegate menu construction pass

After Cocoa loads MainMenu.xib and AppDelegate finishes inserting its two manual menu items, run a **post-construction pass** that walks the relevant menu items and sets each one's `keyEquivalent` / `keyEquivalentModifierMask` from config:

1. For each Veil-owned action in the catalog, locate the corresponding menu item by searching the whole main menu tree for an item whose `action` equals the expected selector. The full selector list is in "Ground Truth: Current Menu Structure" above.
2. Apply the config-derived shortcut via `ShortcutSpec.toMenuKeyEquivalent()`. If the config value is `""` (disabled) or parse failure: clear `keyEquivalent` on the menu item. The item stays visible and clickable.
3. For each menu-handled default vim keymap (the seven entries in the menu-handled table: `saveDocument:`, `undo:`, `redo:`, `cut:`, `copy:`, `paste:`, `selectAll:`), consult `bind_default_keymaps`:
   - If `true`: leave the xib's key equivalents as-is (default behavior preserved).
   - If `false`: clear `keyEquivalent` on these seven items. The menu items stay visible and clickable (manual click still fires the action); only the shortcut is released. The released shortcut then falls through to `NvimView.performKeyEquivalent` and is synthesized as `<D-...>`.

**Helper functions**:
- `findMenuItem(selector:) -> NSMenuItem?` — walk the main menu tree, return the first item whose `action` equals the given selector.
- `applyShortcut(to menuItem: NSMenuItem, spec: ShortcutSpec?)` — apply a spec (or clear if nil).

**Key invariant**: what a menu displays as its shortcut is always what actually triggers the action. If `new_window` is rebound to `cmd+alt+n`, the File menu's "New" item must display `⌥⌘N`.

### Consumer 2: NvimView.performKeyEquivalent

Rewritten to follow the same control flow as the existing code, but driven by the config. Pseudocode:

```
override func performKeyEquivalent(with event: NSEvent) -> Bool:
    // 1. Try the built-in non-menu default vim keymaps.
    //    These are compiled-in ShortcutSpec values for Cmd+1-9,
    //    Ctrl+Tab, Shift+Ctrl+Tab, Shift+Cmd+{, Shift+Cmd+}.
    if VeilConfig.current.keysOrDefault.bind_default_keymaps:
        for (spec, action) in defaultKeymapsDispatchTable:
            if spec.matches(event):
                execute(action)
                return true

    // 2. Let menu items / responder chain handle it.
    //    This catches Cmd+Q, Cmd+N, Cmd+S (when bind_default_keymaps = true), etc.
    if super.performKeyEquivalent(with: event):
        return true

    // 3. Cmd+letter synthesis fallback.
    //    For any Cmd+letter event not already handled by menu or by step 1,
    //    send it to nvim as <D-letter>. This is how Cmd+P, Cmd+J, and any
    //    unbound Cmd+letter reach nvim today, and also how disabled default
    //    keymaps (bind_default_keymaps = false) reach nvim when their menu
    //    items have cleared keyEquivalents.
    if event.modifierFlags.contains(.command),
       let chars = event.charactersIgnoringModifiers,
       !chars.isEmpty:
        let nvimKey = KeyUtils.nvimKey(characters: chars, modifiers: event.modifierFlags)
        Task { await channel?.send(key: nvimKey) }
        return true

    // 4. Non-Cmd events and things we don't handle fall through.
    //    For non-Cmd events this eventually becomes a keyDown: call, where
    //    Veil's existing keyDown logic sends the key to nvim.
    return false
```

Key differences from the current code:

- The hardcoded `Ctrl+Tab`, `Cmd+1-9`, `Shift+Cmd+{/}` branches become entries in a `defaultKeymapsDispatchTable` — a compile-time list of `(ShortcutSpec, NvimDispatchClosure)` pairs. The dispatch closure can be a trivial wrapper around `channel?.command("…")` for fixed commands, or a more flexible closure that computes the command from the matched event (for Cmd+1-9 where each digit maps to a different `:tabnext N`).
- The `systemKeys` whitelist is gone. Its role is replaced by the natural ordering of steps 2 and 3: first let the menu handle it (step 2), then synthesize Cmd+letter (step 3). Step 3 runs only when step 2 returned false, which is exactly when "the menu did not claim this shortcut" — equivalent to "the key is not in `systemKeys`" in the current code.
- The `Cmd+Ctrl+*` exemption (current line 35-38) is still handled correctly: step 2's super call delegates to the menu, which has `Cmd+Ctrl+F` wired to `toggleFullScreen:`, so it returns true without reaching step 3.

### How `bind_default_keymaps = false` Works End-to-End

- **AppDelegate pass** (Consumer 1) clears `keyEquivalent` on the seven menu-handled default vim keymap items (Save, Undo, Redo, Cut, Copy, Paste, Select All). Pressing Cmd+S is no longer matched in step 2 of the menu lookup.
- **performKeyEquivalent** (Consumer 2) skips the step-1 dispatch table because `bind_default_keymaps == false`. Cmd+1, Ctrl+Tab, etc. fall through.
- For Cmd+letter events (Cmd+S, Cmd+1, Cmd+Z, etc.), step 3 synthesizes `<D-s>`, `<D-1>`, `<D-z>`, ... and sends them to nvim.
- For Ctrl+Tab (non-Cmd), step 4 returns false. Cocoa continues event dispatch: Ctrl+Tab becomes a `keyDown:` event and is handled by Veil's existing `keyDown(with:)` path, which sends it to nvim as `<C-Tab>` via `KeyUtils.nvimKey`.
- For Shift+Cmd+} (is-Cmd), step 3 fires: synthesizes `<S-D-}>` via `KeyUtils.nvimKey` (the existing utility outputs modifiers in `C-S-M-D` prefix order, so the explicit Shift flag becomes `S-` before the Cmd flag's `D-`) and sends to nvim.

Both consumers must be synchronized by reading the same `VeilConfig.current.keysOrDefault` — disabling only one side would leave either the menu still catching Cmd+S or the step-1 dispatch table still catching Cmd+1-9, breaking the "all default keymaps pass through to nvim" guarantee.

## Files Changed

- `Veil/Config.swift` — new `KeysConfig` struct, `KeyAction` enum, static default keymap table, `keys` field on `VeilConfig`, `keysOrDefault` accessor, `shortcut(for:)` resolver.
- `Veil/Keybindings/ShortcutSpec.swift` — **new file**. Data types, parser, runtime matching, menu conversion, named key lookup table.
- `Veil/AppDelegate.swift` — post-construction menu pass that reads config and applies key equivalents. Replaces the hardcoded `keyEquivalent: "n"` / `keyEquivalent: "N"` strings in `addConnectRemoteMenuItem` and `addProfilePickerMenuItem` with config lookups (those two functions stay, but their keyEquivalent setup becomes a pass-through call).
- `Veil/Rendering/NvimView+Keyboard.swift` — `performKeyEquivalent` rewritten as config-driven three-step dispatch (see Consumer 2 above). Removes the `systemKeys` whitelist and the hardcoded `Ctrl+Tab` / `Cmd+1-9` / `Shift+Cmd+{/}` branches.
- `veil.sample.toml` — new `[keys]` section as commented-out example.
- `KEYBOARD.md` — **new file** at project root. Six sections: Overview, Shortcut string format, Available key names, Veil-owned actions table, Default Vim keymaps table, Migration cheatsheet.
- `README.md` — simplify Keyboard section (remove long shortcut table, point to KEYBOARD.md). Rewrite the "Full key passthrough" feature line to accurately describe the passthrough behavior.

## KEYBOARD.md Outline

1. **Overview** — The two-category philosophy. Why Veil treats Vim users as owners of their own keymap.
2. **Shortcut string format** — Full grammar with examples. **Important subsection on shifted punctuation**: explain that users write the character Cocoa produces when Shift is applied. Explicitly call out that `shift+cmd+}` is the right way to write the `]` tab-cycling key, and `shift+cmd+]` will not match.
3. **Available key names** — Complete modifier list, complete named key list (34 entries), note on single-character keys.
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
vim.keymap.set('n', '<S-D-}>', 'gt')  -- Shift+Cmd+]
vim.keymap.set('n', '<S-D-{>', 'gT')  -- Shift+Cmd+[
```

**Caveat for Cmd+V**: Veil's default uses `nvim_paste` RPC which handles multi-line bracketed paste correctly. A simple `"+p` mapping does not fully replicate this for insert mode with multi-line content. Users who care about this behavior should either keep `bind_default_keymaps = true` or write a more sophisticated Lua mapping. This caveat is called out in the cheatsheet section.

## Implementation Order

To avoid a broken intermediate state (the old `performKeyEquivalent` assumes the `systemKeys` whitelist and the new menu pass removes implicit assumptions), follow this order:

1. **`ShortcutSpec` + parser + named key table + unit tests.** Self-contained, no dependencies on Veil internals. Pure data-in, data-out.
2. **`KeysConfig` + `KeyAction` + default value table + `VeilConfig` integration + `keysOrDefault` + `shortcut(for:)`.** Still self-contained; no behavioral change to the app yet.
3. **`AppDelegate` menu construction pass.** Apply config-driven key equivalents after menu load. At this stage, because the config has default values matching the xib, the key equivalents are unchanged in behavior. This step is safe to ship independently: existing users see no change.
4. **`NvimView.performKeyEquivalent` rewrite.** Switch from hardcoded branches to the config-driven dispatch table. Again, with default config, behavior is unchanged.
5. **`veil.sample.toml` + `KEYBOARD.md` + `README.md`** — documentation updates.

Steps 3 and 4 must both ship before the feature is actually usable (`bind_default_keymaps = false` doesn't do anything until both paths respect it). Each of steps 3 and 4 is individually a no-op with default config, so they can be reviewed and landed as separate commits without breaking master.

## Verification

### Unit tests
- `ShortcutSpec.parse` covering: all modifier combinations, all named keys, all single-character letters/digits/punctuation, malformed input (empty modifier, unknown modifier, no key, multiple keys, unknown named key), empty string.
- `ShortcutSpec.matches` against synthetic `NSEvent` instances for the above, including:
  - **Modifier flag stripping**: an event with `.function` set (as F-keys naturally do) matches a spec with no modifiers, when the key is `f5`. An event with `.numericPad` set (as arrow keys may on some keyboards) matches a spec with no modifiers, when the key is `up`. An event with `.capsLock` set matches any spec that doesn't specify capsLock (and the spec never specifies capsLock).
  - **Shifted punctuation**: an event produced by pressing Shift+Cmd+] (which has `charactersIgnoringModifiers == "}"`) matches a spec parsed from `"shift+cmd+}"` and does NOT match a spec parsed from `"shift+cmd+]"`.
- `ShortcutSpec.toMenuKeyEquivalent` for: plain letter, shift+letter (uppercase rule), cmd+shift+letter (uppercase rule), cmd+punctuation, cmd+shift+punctuation (passthrough rule — no un-shifting), named key (tab, return).
- **`KeyUtils.nvimKey` round-trip check** (not a new test — existing code path, but worth verifying): for `characters = "}"` and `modifiers = [.shift, .command]`, the function returns `"<S-D-}>"`. This confirms step 3's synthesis branch produces the expected notation for the migration cheatsheet.

### Manual verification
- Existing users' behavior is unchanged with no config file or with empty `[keys]` section (default values from the built-in table match the xib).
- `bind_default_keymaps = false` end-to-end: pressing Cmd+S, Cmd+Z, Cmd+1, Ctrl+Tab, Shift+Cmd+} all reach nvim as `<D-s>`, `<D-z>`, `<D-1>`, `<C-Tab>`, `<D-}>` respectively.
- Shifted-punctuation bindings: verify that `shift+cmd+}` in the default keymap table matches the actual event produced by pressing Shift+Cmd+] on a US layout. Document expected non-US behavior as "may require using the character your layout produces" and consider it out of scope to fix in v1.
- Rebinding: change `new_window = "cmd+alt+n"` in config, confirm the File menu displays `⌥⌘N` and pressing it opens a new window.
- Disabling a Veil-owned action: set `quit = ""`, confirm the App menu's Quit item has no shortcut but remains clickable.
- Malformed config: set `new_window = "cmd+nope+n"`, confirm the stderr log shows a warning, the File menu's "New" item has no shortcut (treated as disabled), other actions are unaffected.
- Duplicate binding: set `new_window = "cmd+w"` (colliding with `close_tab`), observe that the first menu item in traversal order wins. Document in KEYBOARD.md that users are responsible for avoiding collisions.
- **Precedence note**: within `NvimView.performKeyEquivalent`, the built-in default keymap dispatch table (step 1) runs **before** the menu delegation (step 2). So when `bind_default_keymaps = true`, a user who rebinds a Veil-owned action to e.g. `cmd+1` will be silently shadowed by the built-in `:tabnext 1` dispatch. This is called out in KEYBOARD.md so users know not to pick Cmd+1-9, Ctrl+Tab, Shift+Ctrl+Tab, Shift+Cmd+{, or Shift+Cmd+} as rebind targets while default keymaps are enabled.
