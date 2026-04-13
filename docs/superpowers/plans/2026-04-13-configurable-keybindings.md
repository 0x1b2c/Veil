# Configurable Keybindings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Veil's keyboard shortcuts configurable via `veil.toml`, with a single `bind_default_keymaps` switch for default Vim keymaps and per-action rebinding for Veil-owned actions.

**Architecture:** `VeilConfig.current.keys` is the single source of truth. It's consumed in two places: (1) a post-construction menu pass in `AppDelegate` that applies shortcuts to NSMenu items, and (2) a config-driven dispatch table in `NvimView.performKeyEquivalent` for non-menu default keymaps (Cmd+1-9, Ctrl+Tab, Shift+Cmd+{/}). A new `ShortcutSpec` type in `Veil/Keybindings/ShortcutSpec.swift` handles parsing, runtime matching, and NSMenu conversion.

**Tech Stack:** Swift 5.10, XCTest (tests in `VeilTests/`), AppKit, TOML decoding via existing `DecodableDefault.Wrapper` pattern in `Veil/Config.swift`.

**Spec:** `docs/superpowers/specs/2026-04-13-configurable-keybindings-design.md`

---

## Context for the Implementer

Read these before starting:

- `docs/superpowers/specs/2026-04-13-configurable-keybindings-design.md` — the full design spec. All decisions and trade-offs are documented there.
- `Veil/Rendering/NvimView+Keyboard.swift` (lines 7-52) — current hardcoded `performKeyEquivalent` behavior.
- `Veil/AppDelegate.swift` (lines 283-390) — current menu construction and manual menu-item additions.
- `Veil/Base.lproj/MainMenu.xib` — the xib file that defines Veil's main menu structure. All default key equivalents come from here.
- `Veil/Config.swift` — existing `DecodableDefault.Wrapper` pattern for TOML decoding with defaults.
- `Veil/Nvim/KeyUtils.swift` — the utility that converts `(characters, modifiers)` to Vim notation like `<D-s>`, `<S-D-}>`. Modifier prefix order is `C-S-M-D`.
- `VeilTests/KeyUtilsTests.swift` — example of existing test style (XCTest, `@testable import Veil`).

### Cocoa behavior reminders

1. **Shifted punctuation**: `NSEvent.charactersIgnoringModifiers` ignores Cmd/Ctrl/Option but **NOT Shift**. Pressing Shift+Cmd+] on US layout gives `charactersIgnoringModifiers == "}"`, not `"]"`. The spec's convention is that users write the shifted character directly (`shift+cmd+}`).

2. **Cmd+letter doesn't fall through to keyDown**: Cocoa drops Cmd+letter events that no menu/performKeyEquivalent claims. The new `performKeyEquivalent` must synthesize `<D-letter>` sends itself for such events. This mirrors how the current code handles non-`systemKeys` Cmd combinations.

3. **Function keys have `.function` modifier**: Cocoa adds `.function` to F-key events automatically. Arrow keys may have `.numericPad` on some keyboards. Caps Lock is `.capsLock`. `ShortcutSpec.matches` must strip these and compare only against `[.command, .control, .option, .shift]`.

4. **KeyUtils prefix order**: `wrapWithModifiers` in `KeyUtils.swift` emits modifiers in order `C-S-M-D`. So Shift+Cmd+} becomes `<S-D-}>` (not `<D-S-}>`).

### Build and test commands

- `make build` — Release build
- `make debug` — Debug build
- `make test` — Run VeilTests (uses xcodebuild under the hood)
- To run a single test class: `xcodebuild -project Veil.xcodeproj -scheme Veil -derivedDataPath .build -only-testing:VeilTests/ShortcutSpecTests CODE_SIGNING_ALLOWED=NO test -quiet`

### Commit convention

Each task ends with a commit. Commit messages are plain English, describe intent not implementation. Do NOT use conventional commit prefixes like `feat:`, `fix:`. Co-author line is optional for subagent-driven work.

---

## File Structure

Files this plan creates:

- `Veil/Keybindings/ShortcutSpec.swift` — new file. `ShortcutSpec` struct, `Key` enum, `NamedKey` enum, parser, runtime matching, menu conversion, named-key lookup table.
- `VeilTests/ShortcutSpecTests.swift` — new file. Unit tests for parse, matches, toMenuKeyEquivalent.
- `KEYBOARD.md` — new file at project root. Full documentation of keyboard configuration.
- `docs/superpowers/plans/2026-04-13-configurable-keybindings.md` — this plan.

Files this plan modifies:

- `Veil/Config.swift` — add `KeysConfig` struct, `KeyAction` enum, static default table, `keys` field on `VeilConfig`, `keysOrDefault` accessor, `shortcut(for:)` method.
- `Veil/AppDelegate.swift` — add `findMenuItem(selector:)` helper, `applyShortcut(to:spec:)` helper, `applyConfiguredKeyEquivalents()` post-construction pass. Replace hardcoded `keyEquivalent: "n"` / `keyEquivalent: "N"` strings in `addConnectRemoteMenuItem` and `addProfilePickerMenuItem` with config lookups via the new pass.
- `Veil/Rendering/NvimView+Keyboard.swift` — rewrite `performKeyEquivalent` as three-step dispatch. Remove `systemKeys` whitelist and hardcoded `Ctrl+Tab`/`Cmd+1-9`/`Shift+Cmd+{/}` branches. Add private `defaultKeymapsDispatchTable` property.
- `veil.sample.toml` — add commented-out `[keys]` section.
- `README.md` — simplify Keyboard section to point at KEYBOARD.md. Update "Full key passthrough" feature line.

Files this plan does NOT touch:

- `Veil/Base.lproj/MainMenu.xib` — stays as-is. The post-construction pass overrides whatever the xib has at runtime.
- `Veil/Nvim/KeyUtils.swift` — existing utility is reused verbatim.

---

## Phase 1: ShortcutSpec, Parser, Runtime Matching

This phase is self-contained. All tests are unit tests against pure-Swift types, no Veil internals needed.

### Task 1: Create ShortcutSpec data types skeleton

**Files:**
- Create: `Veil/Keybindings/ShortcutSpec.swift`

- [ ] **Step 1: Create the directory and file with data types**

Create `Veil/Keybindings/ShortcutSpec.swift` with just the data types (no parse, no matches, no menu conversion yet):

```swift
import AppKit

/// A parsed keyboard shortcut specification.
///
/// Created from a string like `"cmd+shift+n"` via `ShortcutSpec.parse(_:)`.
/// Used for runtime event matching and NSMenu key equivalent conversion.
struct ShortcutSpec: Equatable {
    let modifiers: NSEvent.ModifierFlags
    let key: Key

    /// The key portion of a shortcut, excluding modifiers.
    enum Key: Equatable {
        /// A single-character key like `a`, `1`, `,`, `/`, `` ` ``.
        /// Matched against `NSEvent.charactersIgnoringModifiers`.
        case character(String)

        /// A special key like `tab`, `f5`, `up`. Matched via keyCode or SpecialKey.
        case named(NamedKey)
    }

    /// Special keys that can't be expressed as a single character.
    enum NamedKey: String, CaseIterable {
        case tab, `return`, escape, space, backspace, delete
        case up, down, left, right
        case home, end, pageUp = "pageup", pageDown = "pagedown"
        case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
        case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20
    }
}
```

Note on `NSEvent.ModifierFlags.Equatable`: `NSEvent.ModifierFlags` is an `OptionSet` and conforms to `Equatable` automatically via its `RawRepresentable` conformance. The `ShortcutSpec` struct's `Equatable` synthesis works out of the box.

- [ ] **Step 2: Verify the file compiles**

Run: `make build`
Expected: build succeeds. The file defines types but nothing uses them yet.

- [ ] **Step 3: Commit**

```bash
git add Veil/Keybindings/ShortcutSpec.swift
git commit -m "Add ShortcutSpec data types for configurable keybindings"
```

### Task 2: Write failing tests for modifier parsing

**Files:**
- Create: `VeilTests/ShortcutSpecTests.swift`
- Modify: Xcode project will need to include both new files

- [ ] **Step 1: Create the test file with modifier parsing tests**

Create `VeilTests/ShortcutSpecTests.swift`:

```swift
import XCTest
@testable import Veil

final class ShortcutSpecTests: XCTestCase {

    // MARK: - Parse: modifiers

    func testParseSingleModifierCmd() {
        let spec = ShortcutSpec.parse("cmd+n")
        XCTAssertEqual(spec?.modifiers, .command)
        XCTAssertEqual(spec?.key, .character("n"))
    }

    func testParseSingleModifierCtrl() {
        let spec = ShortcutSpec.parse("ctrl+a")
        XCTAssertEqual(spec?.modifiers, .control)
        XCTAssertEqual(spec?.key, .character("a"))
    }

    func testParseSingleModifierShift() {
        let spec = ShortcutSpec.parse("shift+a")
        XCTAssertEqual(spec?.modifiers, .shift)
        XCTAssertEqual(spec?.key, .character("a"))
    }

    func testParseSingleModifierAlt() {
        let spec = ShortcutSpec.parse("alt+a")
        XCTAssertEqual(spec?.modifiers, .option)
        XCTAssertEqual(spec?.key, .character("a"))
    }

    func testParseOptionAliasForAlt() {
        let spec = ShortcutSpec.parse("option+a")
        XCTAssertEqual(spec?.modifiers, .option)
    }

    func testParseMultipleModifiers() {
        let spec = ShortcutSpec.parse("cmd+shift+n")
        XCTAssertEqual(spec?.modifiers, [.command, .shift])
        XCTAssertEqual(spec?.key, .character("n"))
    }

    func testParseAllFourModifiers() {
        let spec = ShortcutSpec.parse("cmd+ctrl+shift+alt+n")
        XCTAssertEqual(spec?.modifiers, [.command, .control, .shift, .option])
    }

    func testParseModifiersCaseInsensitive() {
        XCTAssertEqual(ShortcutSpec.parse("CMD+N")?.modifiers, .command)
        XCTAssertEqual(ShortcutSpec.parse("Cmd+N")?.modifiers, .command)
    }

    func testParseWhitespaceTolerance() {
        let spec = ShortcutSpec.parse("cmd + shift + n")
        XCTAssertEqual(spec?.modifiers, [.command, .shift])
        XCTAssertEqual(spec?.key, .character("n"))
    }
}
```

- [ ] **Step 2: Add files to Xcode project and run tests to verify they fail**

The files need to be added to the Xcode project. Since Veil uses synchronized file system groups (modern Xcode), files added under `Veil/` and `VeilTests/` are picked up automatically. Verify by opening Xcode momentarily if needed, but the synchronized group behavior means just creating the files is usually enough.

Run: `make test`
Expected: compilation failure — `ShortcutSpec.parse` does not exist yet.

- [ ] **Step 3: Commit the failing tests**

```bash
git add VeilTests/ShortcutSpecTests.swift
git commit -m "Add failing tests for ShortcutSpec modifier parsing"
```

### Task 3: Implement modifier parsing

**Files:**
- Modify: `Veil/Keybindings/ShortcutSpec.swift`

- [ ] **Step 1: Add the parse method for modifiers + single-character keys**

Add to `ShortcutSpec` in `Veil/Keybindings/ShortcutSpec.swift`:

```swift
extension ShortcutSpec {
    /// Parse a shortcut string like `"cmd+shift+n"` into a `ShortcutSpec`.
    ///
    /// Returns `nil` for empty strings (interpreted by callers as "disabled")
    /// or malformed input.
    static func parse(_ string: String) -> ShortcutSpec? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let tokens = trimmed
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !tokens.isEmpty else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        var keyTokens: [String] = []

        for token in tokens {
            let lower = token.lowercased()
            switch lower {
            case "cmd", "command":
                modifiers.insert(.command)
            case "ctrl", "control":
                modifiers.insert(.control)
            case "shift":
                modifiers.insert(.shift)
            case "alt", "option", "opt":
                modifiers.insert(.option)
            default:
                keyTokens.append(token)
            }
        }

        // Exactly one key token is required.
        guard keyTokens.count == 1 else { return nil }
        let keyToken = keyTokens[0]

        // Try named key first (case-insensitive).
        if let namedKey = NamedKey(rawValue: keyToken.lowercased()) {
            return ShortcutSpec(modifiers: modifiers, key: .named(namedKey))
        }

        // Fall back to single-character key.
        guard keyToken.count == 1 else { return nil }
        return ShortcutSpec(modifiers: modifiers, key: .character(keyToken))
    }
}
```

- [ ] **Step 2: Run the modifier tests**

Run: `make test` (or single test target if available)
Expected: all 9 parsing tests pass. Build still succeeds.

- [ ] **Step 3: Commit**

```bash
git add Veil/Keybindings/ShortcutSpec.swift
git commit -m "Implement ShortcutSpec.parse for modifiers and single-character keys"
```

### Task 4: Named key parsing tests + named key lookup table

**Files:**
- Modify: `VeilTests/ShortcutSpecTests.swift`

- [ ] **Step 1: Add named key parsing tests**

Append to `ShortcutSpecTests`:

```swift
    // MARK: - Parse: named keys

    func testParseNamedKeyTab() {
        let spec = ShortcutSpec.parse("cmd+tab")
        XCTAssertEqual(spec?.modifiers, .command)
        XCTAssertEqual(spec?.key, .named(.tab))
    }

    func testParseNamedKeyReturn() {
        XCTAssertEqual(ShortcutSpec.parse("return")?.key, .named(.return))
    }

    func testParseNamedKeyEscape() {
        XCTAssertEqual(ShortcutSpec.parse("escape")?.key, .named(.escape))
    }

    func testParseNamedKeyArrows() {
        XCTAssertEqual(ShortcutSpec.parse("up")?.key, .named(.up))
        XCTAssertEqual(ShortcutSpec.parse("down")?.key, .named(.down))
        XCTAssertEqual(ShortcutSpec.parse("left")?.key, .named(.left))
        XCTAssertEqual(ShortcutSpec.parse("right")?.key, .named(.right))
    }

    func testParseNamedKeyPageUp() {
        XCTAssertEqual(ShortcutSpec.parse("pageup")?.key, .named(.pageUp))
    }

    func testParseNamedKeyF5() {
        XCTAssertEqual(ShortcutSpec.parse("f5")?.key, .named(.f5))
    }

    func testParseNamedKeyF20() {
        XCTAssertEqual(ShortcutSpec.parse("f20")?.key, .named(.f20))
    }

    func testParseNamedKeyCaseInsensitive() {
        XCTAssertEqual(ShortcutSpec.parse("Tab")?.key, .named(.tab))
        XCTAssertEqual(ShortcutSpec.parse("PAGEUP")?.key, .named(.pageUp))
        XCTAssertEqual(ShortcutSpec.parse("F5")?.key, .named(.f5))
    }
```

- [ ] **Step 2: Run tests**

Run: `make test`
Expected: new tests pass — `NamedKey` already has all these cases from Task 1, and the parse function from Task 3 already uses `NamedKey(rawValue:)`.

- [ ] **Step 3: Commit**

```bash
git add VeilTests/ShortcutSpecTests.swift
git commit -m "Add tests for ShortcutSpec named key parsing"
```

### Task 5: Parse error cases

**Files:**
- Modify: `VeilTests/ShortcutSpecTests.swift`

- [ ] **Step 1: Add error case tests**

Append:

```swift
    // MARK: - Parse: error cases

    func testParseEmptyStringReturnsNil() {
        XCTAssertNil(ShortcutSpec.parse(""))
    }

    func testParseWhitespaceOnlyReturnsNil() {
        XCTAssertNil(ShortcutSpec.parse("   "))
    }

    func testParseNoKeyReturnsNil() {
        XCTAssertNil(ShortcutSpec.parse("cmd+shift"))
    }

    func testParseOnlyModifierShiftReturnsNil() {
        XCTAssertNil(ShortcutSpec.parse("shift"))
    }

    func testParseOnlyModifierCmdReturnsNil() {
        XCTAssertNil(ShortcutSpec.parse("cmd"))
    }

    func testParseMultipleKeysReturnsNil() {
        XCTAssertNil(ShortcutSpec.parse("cmd+a+b"))
    }

    func testParseMultiCharKeyWithoutNamedMatchReturnsNil() {
        XCTAssertNil(ShortcutSpec.parse("cmd+nope"))
    }

    func testParseConsecutivePlusParsesAsNormal() {
        // Swift's split(separator:) defaults to omittingEmptySubsequences: true,
        // so "cmd++n" parses the same as "cmd+n". Documenting this behavior.
        let spec = ShortcutSpec.parse("cmd++n")
        XCTAssertEqual(spec?.modifiers, .command)
        XCTAssertEqual(spec?.key, .character("n"))
    }
```

- [ ] **Step 2: Run tests**

Run: `make test`
Expected: all error-case tests pass. `cmd+shift` produces zero key tokens → fails `count == 1`. `shift` and `cmd` same. `cmd+a+b` produces two key tokens → fails `count == 1`. `cmd+nope` produces one multi-character non-named token → fails the single-character check. `cmd++n` benefits from Swift's default `omittingEmptySubsequences: true` and parses as `cmd+n`.

- [ ] **Step 3: Commit**

```bash
git add VeilTests/ShortcutSpecTests.swift
git commit -m "Add parser error case tests for ShortcutSpec"
```

### Task 6: Runtime matching for single-character keys

**Files:**
- Modify: `Veil/Keybindings/ShortcutSpec.swift`
- Modify: `VeilTests/ShortcutSpecTests.swift`

- [ ] **Step 1: Write failing tests for `matches(_:)`**

Append to `ShortcutSpecTests`:

```swift
    // MARK: - Matches: single-character keys

    /// Build a synthetic keyDown NSEvent with given characters and modifiers.
    private func makeKeyDown(
        chars: String,
        charsIgnoringMods: String? = nil,
        modifiers: NSEvent.ModifierFlags = [],
        keyCode: UInt16 = 0
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: charsIgnoringMods ?? chars,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    func testMatchesSimpleCharWithCmd() {
        let spec = ShortcutSpec.parse("cmd+s")!
        let event = makeKeyDown(chars: "s", modifiers: .command)
        XCTAssertTrue(spec.matches(event))
    }

    func testDoesNotMatchWhenModifiersDiffer() {
        let spec = ShortcutSpec.parse("cmd+s")!
        let event = makeKeyDown(chars: "s", modifiers: .control)
        XCTAssertFalse(spec.matches(event))
    }

    func testMatchesCaseInsensitive() {
        // Spec parsed as lowercase "a", but event has uppercase "A"
        let spec = ShortcutSpec.parse("cmd+a")!
        let event = makeKeyDown(chars: "A", modifiers: .command)
        XCTAssertTrue(spec.matches(event))
    }

    // MARK: - Matches: modifier flag stripping

    func testMatchesIgnoresFunctionFlag() {
        // F5 events have .function set automatically
        let spec = ShortcutSpec.parse("f5")!
        let event = makeKeyDown(
            chars: String(Character(UnicodeScalar(NSF5FunctionKey)!)),
            modifiers: .function,
            keyCode: 96)
        XCTAssertTrue(spec.matches(event))
    }

    func testMatchesIgnoresNumericPadFlag() {
        let spec = ShortcutSpec.parse("up")!
        let event = makeKeyDown(
            chars: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)),
            modifiers: [.function, .numericPad],
            keyCode: 126)
        XCTAssertTrue(spec.matches(event))
    }

    func testMatchesIgnoresCapsLock() {
        let spec = ShortcutSpec.parse("cmd+s")!
        let event = makeKeyDown(chars: "s", modifiers: [.command, .capsLock])
        XCTAssertTrue(spec.matches(event))
    }

    // MARK: - Matches: shifted punctuation

    func testMatchesShiftedPunctuationCloseBrace() {
        // Shift+Cmd+] produces charactersIgnoringModifiers == "}"
        let spec = ShortcutSpec.parse("shift+cmd+}")!
        let event = makeKeyDown(
            chars: "}",
            charsIgnoringMods: "}",
            modifiers: [.shift, .command])
        XCTAssertTrue(spec.matches(event))
    }

    func testDoesNotMatchUnshiftedVersionWhenShiftedProduced() {
        // A spec for "shift+cmd+]" does NOT match the event (which produces "}")
        let spec = ShortcutSpec.parse("shift+cmd+]")!
        let event = makeKeyDown(
            chars: "}",
            charsIgnoringMods: "}",
            modifiers: [.shift, .command])
        XCTAssertFalse(spec.matches(event))
    }
```

Run: `make test`
Expected: compile failure — `matches(_:)` doesn't exist.

- [ ] **Step 2: Implement `matches(_:)` for single-char and flag stripping**

Add to `Veil/Keybindings/ShortcutSpec.swift`:

```swift
extension ShortcutSpec {
    /// Returns true if the given keyboard event matches this shortcut spec.
    func matches(_ event: NSEvent) -> Bool {
        // Compare modifiers, ignoring .function, .numericPad, .capsLock, and
        // other flags Cocoa sets automatically but that aren't part of a shortcut.
        let relevantMask: NSEvent.ModifierFlags =
            [.command, .control, .option, .shift]
        let eventMods = event.modifierFlags.intersection(relevantMask)
        guard eventMods == self.modifiers else { return false }

        switch self.key {
        case .character(let c):
            guard let eventChars = event.charactersIgnoringModifiers else { return false }
            return eventChars.lowercased() == c.lowercased()
        case .named(let namedKey):
            return matchesNamedKey(namedKey, event: event)
        }
    }

    private func matchesNamedKey(_ namedKey: NamedKey, event: NSEvent) -> Bool {
        // Implemented in Task 7.
        return false
    }
}
```

- [ ] **Step 3: Run tests**

Run: `make test`
Expected: single-char / case-insensitive / flag stripping / shifted punctuation tests pass. F5 / arrow tests still fail (named key matching not implemented).

- [ ] **Step 4: Commit**

```bash
git add Veil/Keybindings/ShortcutSpec.swift VeilTests/ShortcutSpecTests.swift
git commit -m "Implement ShortcutSpec.matches for single-character keys and flag stripping"
```

### Task 7: Runtime matching for named keys

**Files:**
- Modify: `Veil/Keybindings/ShortcutSpec.swift`

- [ ] **Step 1: Implement the named key matcher**

Replace the `matchesNamedKey` stub in `ShortcutSpec.swift` with:

```swift
    private func matchesNamedKey(_ namedKey: NamedKey, event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers,
              let scalar = chars.unicodeScalars.first
        else { return false }
        let code = Int(scalar.value)

        switch namedKey {
        case .up: return code == NSUpArrowFunctionKey
        case .down: return code == NSDownArrowFunctionKey
        case .left: return code == NSLeftArrowFunctionKey
        case .right: return code == NSRightArrowFunctionKey
        case .home: return code == NSHomeFunctionKey
        case .end: return code == NSEndFunctionKey
        case .pageUp: return code == NSPageUpFunctionKey
        case .pageDown: return code == NSPageDownFunctionKey
        case .delete: return code == NSDeleteFunctionKey
        case .tab: return code == 0x09
        case .return: return code == 0x0D
        case .escape: return code == 0x1B
        case .space: return code == 0x20
        case .backspace: return code == 0x7F
        case .f1: return code == NSF1FunctionKey
        case .f2: return code == NSF2FunctionKey
        case .f3: return code == NSF3FunctionKey
        case .f4: return code == NSF4FunctionKey
        case .f5: return code == NSF5FunctionKey
        case .f6: return code == NSF6FunctionKey
        case .f7: return code == NSF7FunctionKey
        case .f8: return code == NSF8FunctionKey
        case .f9: return code == NSF9FunctionKey
        case .f10: return code == NSF10FunctionKey
        case .f11: return code == NSF11FunctionKey
        case .f12: return code == NSF12FunctionKey
        case .f13: return code == NSF13FunctionKey
        case .f14: return code == NSF14FunctionKey
        case .f15: return code == NSF15FunctionKey
        case .f16: return code == NSF16FunctionKey
        case .f17: return code == NSF17FunctionKey
        case .f18: return code == NSF18FunctionKey
        case .f19: return code == NSF19FunctionKey
        case .f20: return code == NSF20FunctionKey
        }
    }
```

Note on `backspace` vs `delete`: On macOS, the main Delete key (⌫, top-right of the alpha block, labeled Delete) sends `0x7F` — Vim calls this `<BS>`. The Forward Delete key (⌦, on full-size keyboards) sends `NSDeleteFunctionKey`. In Veil's shortcut string format, `backspace` refers to ⌫ (main Delete) and `delete` refers to ⌦ (Forward Delete). Each key has exactly one spec name, so there's no duplicate-matching footgun where both `cmd+delete` and `cmd+backspace` match the same physical key. This matches the behavior of `KeyUtils.nvimKey` (see existing `KeyUtils.swift` lines 11-12, where `0x7F` maps to `<BS>` and `NSDeleteFunctionKey` maps to `<Del>`).

- [ ] **Step 2: Run tests**

Run: `make test`
Expected: all `matches` tests pass, including F5 and arrow keys.

- [ ] **Step 3: Commit**

```bash
git add Veil/Keybindings/ShortcutSpec.swift
git commit -m "Implement ShortcutSpec named key matching for arrows, function keys, and editing keys"
```

### Task 8: `toMenuKeyEquivalent` for letters and punctuation

**Files:**
- Modify: `Veil/Keybindings/ShortcutSpec.swift`
- Modify: `VeilTests/ShortcutSpecTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `ShortcutSpecTests`:

```swift
    // MARK: - toMenuKeyEquivalent

    func testMenuEquivalentSimpleLetter() {
        let (key, mask) = ShortcutSpec.parse("cmd+n")!.toMenuKeyEquivalent()!
        XCTAssertEqual(key, "n")
        XCTAssertEqual(mask, .command)
    }

    func testMenuEquivalentShiftLetterUsesUppercase() {
        let (key, mask) = ShortcutSpec.parse("cmd+shift+n")!.toMenuKeyEquivalent()!
        XCTAssertEqual(key, "N")
        XCTAssertEqual(mask, [.command, .shift])
    }

    func testMenuEquivalentShiftPunctuationPassthrough() {
        let (key, mask) = ShortcutSpec.parse("cmd+shift+}")!.toMenuKeyEquivalent()!
        XCTAssertEqual(key, "}")
        XCTAssertEqual(mask, [.command, .shift])
    }

    func testMenuEquivalentDigitPassthrough() {
        let (key, mask) = ShortcutSpec.parse("cmd+1")!.toMenuKeyEquivalent()!
        XCTAssertEqual(key, "1")
        XCTAssertEqual(mask, .command)
    }

    func testMenuEquivalentComma() {
        let (key, mask) = ShortcutSpec.parse("cmd+,")!.toMenuKeyEquivalent()!
        XCTAssertEqual(key, ",")
        XCTAssertEqual(mask, .command)
    }
```

Run: `make test`
Expected: compile failure — `toMenuKeyEquivalent()` doesn't exist.

- [ ] **Step 2: Implement `toMenuKeyEquivalent`**

Add to `Veil/Keybindings/ShortcutSpec.swift`:

```swift
extension ShortcutSpec {
    /// Convert to NSMenu's keyEquivalent + modifierMask form.
    ///
    /// For ASCII letters with Shift set, uses the uppercase letter and keeps
    /// `.shift` in the mask (unambiguous form). Digits and punctuation pass
    /// through verbatim — the caller is expected to write the shifted glyph
    /// directly (e.g., `cmd+shift+}`, not `cmd+shift+]`).
    ///
    /// Returns `nil` for named keys without a standard NSMenu representation.
    func toMenuKeyEquivalent() -> (String, NSEvent.ModifierFlags)? {
        switch self.key {
        case .character(let c):
            let hasShift = modifiers.contains(.shift)
            let isAsciiLetter = c.count == 1
                && c.unicodeScalars.first.map { $0.isASCII && $0.properties.isAlphabetic } == true
            let keyString = (hasShift && isAsciiLetter) ? c.uppercased() : c
            return (keyString, modifiers)
        case .named(let namedKey):
            return namedKey.menuCharacter.map { ($0, modifiers) }
        }
    }
}

extension ShortcutSpec.NamedKey {
    /// The string NSMenu uses as `keyEquivalent` for this named key, if any.
    var menuCharacter: String? {
        switch self {
        case .tab: return "\t"
        case .return: return "\r"
        case .escape: return "\u{1B}"
        case .space: return " "
        case .backspace: return "\u{8}"
        case .delete: return "\u{7F}"
        case .up: return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        case .down: return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        case .left: return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        case .right: return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        case .home: return String(Character(UnicodeScalar(NSHomeFunctionKey)!))
        case .end: return String(Character(UnicodeScalar(NSEndFunctionKey)!))
        case .pageUp: return String(Character(UnicodeScalar(NSPageUpFunctionKey)!))
        case .pageDown: return String(Character(UnicodeScalar(NSPageDownFunctionKey)!))
        case .f1: return String(Character(UnicodeScalar(NSF1FunctionKey)!))
        case .f2: return String(Character(UnicodeScalar(NSF2FunctionKey)!))
        case .f3: return String(Character(UnicodeScalar(NSF3FunctionKey)!))
        case .f4: return String(Character(UnicodeScalar(NSF4FunctionKey)!))
        case .f5: return String(Character(UnicodeScalar(NSF5FunctionKey)!))
        case .f6: return String(Character(UnicodeScalar(NSF6FunctionKey)!))
        case .f7: return String(Character(UnicodeScalar(NSF7FunctionKey)!))
        case .f8: return String(Character(UnicodeScalar(NSF8FunctionKey)!))
        case .f9: return String(Character(UnicodeScalar(NSF9FunctionKey)!))
        case .f10: return String(Character(UnicodeScalar(NSF10FunctionKey)!))
        case .f11: return String(Character(UnicodeScalar(NSF11FunctionKey)!))
        case .f12: return String(Character(UnicodeScalar(NSF12FunctionKey)!))
        case .f13: return String(Character(UnicodeScalar(NSF13FunctionKey)!))
        case .f14: return String(Character(UnicodeScalar(NSF14FunctionKey)!))
        case .f15: return String(Character(UnicodeScalar(NSF15FunctionKey)!))
        case .f16: return String(Character(UnicodeScalar(NSF16FunctionKey)!))
        case .f17: return String(Character(UnicodeScalar(NSF17FunctionKey)!))
        case .f18: return String(Character(UnicodeScalar(NSF18FunctionKey)!))
        case .f19: return String(Character(UnicodeScalar(NSF19FunctionKey)!))
        case .f20: return String(Character(UnicodeScalar(NSF20FunctionKey)!))
        }
    }
}
```

- [ ] **Step 3: Run tests**

Run: `make test`
Expected: all menu equivalent tests pass.

- [ ] **Step 4: Commit**

```bash
git add Veil/Keybindings/ShortcutSpec.swift VeilTests/ShortcutSpecTests.swift
git commit -m "Implement ShortcutSpec.toMenuKeyEquivalent for letters, digits, punctuation, and named keys"
```

---

## Phase 2: KeysConfig and VeilConfig Integration

### Task 9: KeyAction enum and default table

**Files:**
- Modify: `Veil/Config.swift`

- [ ] **Step 1: Add KeyAction enum and default shortcut table**

Add to `Veil/Config.swift` (near the other enums at the top):

```swift
// MARK: - KeyAction

/// Identifies a Veil-owned action that can be bound to a keyboard shortcut.
enum KeyAction: String, CaseIterable {
    case newWindow = "new_window"
    case newWindowWithProfile = "new_window_with_profile"
    case closeTab = "close_tab"
    case closeWindow = "close_window"
    case quit
    case hide
    case minimize
    case toggleFullscreen = "toggle_fullscreen"
    case openSettings = "open_settings"
    case connectRemote = "connect_remote"

    /// The selector that this action's menu item uses. Used by AppDelegate's
    /// post-construction pass to locate the right menu item.
    ///
    /// We use `NSSelectorFromString` rather than `#selector(...)` because
    /// several of these selectors resolve to methods on classes that aren't
    /// visible from `Config.swift` (e.g., `NvimView.saveDocument`, or Cocoa's
    /// `NSApplication.terminate`). Using the string form keeps this file
    /// free of cross-module dependencies.
    var selector: Selector {
        switch self {
        case .newWindow: return NSSelectorFromString("newDocument:")
        case .newWindowWithProfile: return NSSelectorFromString("newDocumentWithProfilePicker:")
        case .closeTab: return NSSelectorFromString("closeTabOrWindow:")
        case .closeWindow: return NSSelectorFromString("closeWindow:")
        case .quit: return NSSelectorFromString("terminate:")
        case .hide: return NSSelectorFromString("hide:")
        case .minimize: return NSSelectorFromString("performMiniaturize:")
        case .toggleFullscreen: return NSSelectorFromString("toggleFullScreen:")
        case .openSettings: return NSSelectorFromString("openSettings:")
        case .connectRemote: return NSSelectorFromString("connectToRemote:")
        }
    }

    /// Built-in default shortcut string for this action.
    var defaultShortcut: String {
        switch self {
        case .newWindow: return "cmd+n"
        case .newWindowWithProfile: return "cmd+shift+n"
        case .closeTab: return "cmd+w"
        case .closeWindow: return "cmd+shift+w"
        case .quit: return "cmd+q"
        case .hide: return "cmd+h"
        case .minimize: return "cmd+m"
        case .toggleFullscreen: return "cmd+ctrl+f"
        case .openSettings: return "cmd+,"
        case .connectRemote: return "cmd+ctrl+shift+n"
        }
    }
}
```

Note on `NSSelectorFromString`: this is the documented Cocoa API for runtime string-based selectors. It's clearer than `Selector(("..."))` (a double-paren workaround that suppresses warnings) and keeps `Config.swift` free of cross-module imports.

- [ ] **Step 2: Build**

Run: `make build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Veil/Config.swift
git commit -m "Add KeyAction enum with default shortcuts and selector mapping"
```

### Task 10: KeysConfig struct and decoding

**Files:**
- Modify: `Veil/Config.swift`

- [ ] **Step 1: Add KeysConfig struct**

Add to `Veil/Config.swift` (after `RemoteEntry`):

```swift
// MARK: - KeysConfig

struct KeysConfig: Decodable {
    @DecodableDefault.Wrapper<DecodableDefault.True>
    var bind_default_keymaps: Bool

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

    /// Returns the user's value for the given action, or the built-in default
    /// if the user didn't specify one.
    func rawShortcut(for action: KeyAction) -> String {
        let userValue: String?
        switch action {
        case .newWindow: userValue = new_window
        case .newWindowWithProfile: userValue = new_window_with_profile
        case .closeTab: userValue = close_tab
        case .closeWindow: userValue = close_window
        case .quit: userValue = quit
        case .hide: userValue = hide
        case .minimize: userValue = minimize
        case .toggleFullscreen: userValue = toggle_fullscreen
        case .openSettings: userValue = open_settings
        case .connectRemote: userValue = connect_remote
        }
        return userValue ?? action.defaultShortcut
    }

    /// Returns the parsed ShortcutSpec for the given action, or `nil` if the
    /// user disabled it (empty string) or the string fails to parse.
    func shortcut(for action: KeyAction) -> ShortcutSpec? {
        let raw = rawShortcut(for: action)
        if raw.isEmpty { return nil }
        if let spec = ShortcutSpec.parse(raw) { return spec }
        // Malformed: log and treat as disabled.
        NSLog("Veil: malformed shortcut '\(raw)' for \(action.rawValue); treated as disabled")
        return nil
    }

    init() {}
}
```

Note on `init()`: the empty initializer is needed so `VeilConfig.keysOrDefault` can return a default-constructed `KeysConfig()` when the user didn't provide a `[keys]` section. Because `KeysConfig` is `Decodable` with all-optional or defaulted fields, Swift should synthesize a parameterless init automatically — but making it explicit is safer.

- [ ] **Step 2: Add `keys` field and `keysOrDefault` to `VeilConfig`**

In the `VeilConfig` struct, add:

```swift
    var keys: KeysConfig?

    var keysOrDefault: KeysConfig {
        keys ?? KeysConfig()
    }
```

- [ ] **Step 3: Build**

Run: `make build`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Veil/Config.swift
git commit -m "Add KeysConfig decoding with per-action defaults and shortcut resolver"
```

### Task 11: Sanity test for KeysConfig defaults

**Files:**
- Modify: `VeilTests/ShortcutSpecTests.swift` (or create a new test file)

- [ ] **Step 1: Add a small test verifying KeysConfig defaults**

Append to `ShortcutSpecTests.swift` (or create `VeilTests/KeysConfigTests.swift` if you prefer separation):

```swift
    // MARK: - KeysConfig integration

    func testKeysConfigDefaultBindDefaultKeymapsIsTrue() {
        let config = KeysConfig()
        XCTAssertTrue(config.bind_default_keymaps)
    }

    func testKeysConfigDefaultShortcutForNewWindow() {
        let config = KeysConfig()
        let spec = config.shortcut(for: .newWindow)
        XCTAssertEqual(spec?.modifiers, .command)
        XCTAssertEqual(spec?.key, .character("n"))
    }

    func testKeysConfigEmptyStringDisablesAction() {
        var config = KeysConfig()
        config.new_window = ""
        XCTAssertNil(config.shortcut(for: .newWindow))
    }

    func testKeysConfigMalformedStringReturnsNil() {
        var config = KeysConfig()
        config.new_window = "not-a-valid-shortcut"
        XCTAssertNil(config.shortcut(for: .newWindow))
    }

    func testKeyActionDefaultShortcutsAllParse() {
        for action in KeyAction.allCases {
            XCTAssertNotNil(
                ShortcutSpec.parse(action.defaultShortcut),
                "Default shortcut '\(action.defaultShortcut)' for \(action.rawValue) failed to parse")
        }
    }

    // MARK: - KeyUtils round-trip (integration check)

    /// Verify that KeyUtils.nvimKey produces the Vim notation the migration
    /// cheatsheet promises. These are the notations nvim receives in step 3
    /// of `performKeyEquivalent` when `bind_default_keymaps = false`.
    func testKeyUtilsNvimKeyForShiftedPunctuation() {
        XCTAssertEqual(
            KeyUtils.nvimKey(characters: "}", modifiers: [.shift, .command]),
            "<S-D-}>")
        XCTAssertEqual(
            KeyUtils.nvimKey(characters: "{", modifiers: [.shift, .command]),
            "<S-D-{>")
    }

    func testKeyUtilsNvimKeyForShiftedLetter() {
        XCTAssertEqual(
            KeyUtils.nvimKey(characters: "z", modifiers: [.shift, .command]),
            "<S-D-z>")
    }
```

Note: `@DecodableDefault.Wrapper` property wrappers have `var wrappedValue = S.defaultValue` so the default-initialized `KeysConfig()` should have `bind_default_keymaps = true`. Verify this works — if not, the test will reveal a wrapper initialization issue and you may need an explicit `bind_default_keymaps` setter.

- [ ] **Step 2: Run tests**

Run: `make test`
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add VeilTests/ShortcutSpecTests.swift
git commit -m "Add KeysConfig default and disable tests"
```

---

## Phase 3: AppDelegate Menu Construction Pass

### Task 12: `findMenuItem(selector:)` helper and dry-run verification

**Files:**
- Modify: `Veil/AppDelegate.swift`

- [ ] **Step 1: Add a private helper to walk the main menu tree**

Add inside the `AppDelegate` class (near the existing menu-setup helpers):

```swift
    /// Recursively search the main menu tree for an item with the given action selector.
    /// Returns the first match, or nil.
    private func findMenuItem(selector: Selector) -> NSMenuItem? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        return findMenuItem(selector: selector, in: mainMenu)
    }

    private func findMenuItem(selector: Selector, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.action == selector {
                return item
            }
            if let submenu = item.submenu,
               let found = findMenuItem(selector: selector, in: submenu)
            {
                return found
            }
        }
        return nil
    }
```

- [ ] **Step 2: Build and verify no regressions**

Run: `make build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Veil/AppDelegate.swift
git commit -m "Add findMenuItem(selector:) helper for menu tree traversal"
```

### Task 13: Post-construction menu pass for Veil-owned actions

**Files:**
- Modify: `Veil/AppDelegate.swift`

- [ ] **Step 1: Add the post-construction pass**

Add to `AppDelegate`:

```swift
    /// Apply config-driven shortcuts to menu items.
    ///
    /// Must be called after the main menu has been loaded from the xib AND
    /// after AppDelegate's manual menu-item additions (profile picker, connect
    /// remote). Overwrites any key equivalents set in the xib with values from
    /// `VeilConfig.current.keysOrDefault`.
    private func applyConfiguredKeyEquivalents() {
        let keys = VeilConfig.current.keysOrDefault

        // 1. Veil-owned actions: read per-action config and apply.
        for action in KeyAction.allCases {
            guard let item = findMenuItem(selector: action.selector) else {
                NSLog("Veil: could not find menu item for \(action.rawValue)")
                continue
            }
            applyShortcut(to: item, spec: keys.shortcut(for: action))
        }

        // 2. Default Vim keymaps — the menu-handled subset.
        //    If bind_default_keymaps is false, clear the key equivalents on
        //    these menu items so the keys fall through to performKeyEquivalent
        //    and are synthesized as <D-...> for nvim.
        if !keys.bind_default_keymaps {
            let defaultKeymapSelectors: [Selector] = [
                NSSelectorFromString("saveDocument:"),
                NSSelectorFromString("undo:"),
                NSSelectorFromString("redo:"),
                NSSelectorFromString("cut:"),
                NSSelectorFromString("copy:"),
                NSSelectorFromString("paste:"),
                NSSelectorFromString("selectAll:"),
            ]
            for selector in defaultKeymapSelectors {
                if let item = findMenuItem(selector: selector) {
                    item.keyEquivalent = ""
                    item.keyEquivalentModifierMask = []
                }
            }
        }
    }

    /// Apply a ShortcutSpec (or nil for disabled) to a menu item.
    private func applyShortcut(to item: NSMenuItem, spec: ShortcutSpec?) {
        if let spec, let (key, mask) = spec.toMenuKeyEquivalent() {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = mask
        } else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
        }
    }
```

- [ ] **Step 2: Build**

Run: `make build`
Expected: build succeeds. The pass is defined but not called yet.

- [ ] **Step 3: Commit**

```bash
git add Veil/AppDelegate.swift
git commit -m "Add applyConfiguredKeyEquivalents post-construction menu pass"
```

### Task 14: Wire the pass into AppDelegate startup

**Files:**
- Modify: `Veil/AppDelegate.swift`

- [ ] **Step 1: Find the existing menu setup call site**

Look for where `addDebugOverlayMenuItem()`, `addConnectRemoteMenuItem()`, and `addProfilePickerMenuItem()` are called. They should all be in `applicationDidFinishLaunching(_:)` or a similar early startup method.

Run: `grep -n "addDebugOverlayMenuItem\|addConnectRemoteMenuItem\|addProfilePickerMenuItem" Veil/AppDelegate.swift`

- [ ] **Step 2: Call `applyConfiguredKeyEquivalents()` after all menu additions**

Add `applyConfiguredKeyEquivalents()` as the LAST step in that sequence, so it can override whatever the xib and manual additions set:

```swift
// In applicationDidFinishLaunching or wherever menu setup happens:
addDebugOverlayMenuItem()
addConnectRemoteMenuItem()
addProfilePickerMenuItem()
applyConfiguredKeyEquivalents()   // <-- new
```

- [ ] **Step 3: Build**

Run: `make build`
Expected: build succeeds.

- [ ] **Step 4: Manually verify (optional but recommended)**

Run `make install && open -a Veil`. With no `veil.toml` changes, all menus should display the same shortcuts as before. Open File menu and Edit menu to visually confirm.

- [ ] **Step 5: Commit**

```bash
git add Veil/AppDelegate.swift
git commit -m "Apply configured key equivalents on startup"
```

### Task 15: Verify the pass with a rebind test

**Files:**
- None (manual test)

- [ ] **Step 1: Create a temporary veil.toml with a rebind**

Edit `~/.config/veil/veil.toml` to add:

```toml
[keys]
new_window = "cmd+alt+n"
```

- [ ] **Step 2: Rebuild, relaunch, and verify**

Run: `make install && open -a Veil`
Expected: File menu's "New" item shows `⌥⌘N` instead of `⌘N`. Pressing `⌥⌘N` opens a new window. Pressing `⌘N` no longer opens a new window (it should synthesize `<D-n>` to nvim instead, which may have no binding — this is fine, just means no action).

- [ ] **Step 3: Restore the config**

Remove the `[keys]` section or comment it out.

- [ ] **Step 4: No commit (manual verification only)**

---

## Phase 4: NvimView.performKeyEquivalent Rewrite

### Task 16: Build the default keymap dispatch table

**Files:**
- Modify: `Veil/Rendering/NvimView+Keyboard.swift`

- [ ] **Step 1: Add the dispatch table type and instance**

Near the top of the `NvimView` extension in `NvimView+Keyboard.swift`, add:

```swift
// MARK: - Default Vim keymaps dispatch table

/// A default keymap entry: the shortcut spec and a closure that runs when matched.
/// The closure receives the matched NSEvent in case the dispatch needs information
/// from it (e.g., Cmd+1-9 uses the digit from the event).
///
/// The closure is `@MainActor`-isolated because `NvimView` is an `NSView` subclass
/// and therefore main-actor-bound. This matches how `performKeyEquivalent` itself
/// is invoked, so calling the closure from there is allowed without `await`.
private struct DefaultKeymapEntry {
    let spec: ShortcutSpec
    let dispatch: @MainActor (NvimView, NSEvent) -> Void
}

/// Default vim keymaps that are dispatched from performKeyEquivalent
/// (as opposed to via menu items). These are the ones that aren't owned
/// by any menu: Cmd+1-9, Ctrl+Tab, Shift+Ctrl+Tab, Shift+Cmd+{/}.
private let nonMenuDefaultKeymaps: [DefaultKeymapEntry] = {
    var entries: [DefaultKeymapEntry] = []

    // Cmd+1 through Cmd+8: switch to tab N.
    for digit in 1...8 {
        guard let spec = ShortcutSpec.parse("cmd+\(digit)") else { continue }
        entries.append(DefaultKeymapEntry(spec: spec) { view, _ in
            Task { try? await view.channel?.command("tabnext \(digit)") }
        })
    }

    // Cmd+9: switch to last tab.
    if let spec = ShortcutSpec.parse("cmd+9") {
        entries.append(DefaultKeymapEntry(spec: spec) { view, _ in
            Task { try? await view.channel?.command("tablast") }
        })
    }

    // Ctrl+Tab: next tab.
    if let spec = ShortcutSpec.parse("ctrl+tab") {
        entries.append(DefaultKeymapEntry(spec: spec) { view, _ in
            Task { try? await view.channel?.command("tabnext") }
        })
    }

    // Shift+Ctrl+Tab: previous tab.
    if let spec = ShortcutSpec.parse("shift+ctrl+tab") {
        entries.append(DefaultKeymapEntry(spec: spec) { view, _ in
            Task { try? await view.channel?.command("tabprevious") }
        })
    }

    // Shift+Cmd+}: next tab. (Note: the user presses Shift+Cmd+] which
    // produces `}` via Cocoa's shifted-punctuation behavior.)
    if let spec = ShortcutSpec.parse("shift+cmd+}") {
        entries.append(DefaultKeymapEntry(spec: spec) { view, _ in
            Task { try? await view.channel?.command("tabnext") }
        })
    }

    // Shift+Cmd+{: previous tab. (User presses Shift+Cmd+[.)
    if let spec = ShortcutSpec.parse("shift+cmd+{") {
        entries.append(DefaultKeymapEntry(spec: spec) { view, _ in
            Task { try? await view.channel?.command("tabprevious") }
        })
    }

    return entries
}()
```

Note on the file-private `let`: we use a top-level `private let` instead of a static property to keep the initialization simple. The table is built once at module load.

Note on capturing: closures reference the view parameter, not `self`. This avoids retain cycles and lets us store the table globally.

- [ ] **Step 2: Build**

Run: `make build`
Expected: build succeeds. The table exists but isn't referenced yet.

- [ ] **Step 3: Commit**

```bash
git add Veil/Rendering/NvimView+Keyboard.swift
git commit -m "Add non-menu default keymap dispatch table"
```

### Task 17: Rewrite `performKeyEquivalent`

**Files:**
- Modify: `Veil/Rendering/NvimView+Keyboard.swift`

- [ ] **Step 1: Replace the existing `performKeyEquivalent` body**

Locate the existing `performKeyEquivalent(with:)` method (lines 7-52 as of the spec's writing). Replace its entire body with:

```swift
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let keys = VeilConfig.current.keysOrDefault

        // Step 1: try the non-menu default keymap dispatch table.
        //         Skipped when bind_default_keymaps is false — the keys
        //         then fall through to step 3 for <D-...> synthesis (for
        //         Cmd+ events) or to keyDown (for Ctrl+Tab etc).
        if keys.bind_default_keymaps {
            for entry in nonMenuDefaultKeymaps {
                if entry.spec.matches(event) {
                    entry.dispatch(self, event)
                    return true
                }
            }
        }

        // Step 2: NSView's default subview walk. The main menu has already
        //         been consulted by NSApplication before this method runs —
        //         Cmd+Q, Cmd+N, Cmd+S, Cmd+` (via macOS's auto-injected
        //         Window menu cycling), etc. are intercepted at the NSApp
        //         level when their menu items have a keyEquivalent set.
        //         This `super` call only matters if some subview wants to
        //         claim the event; in practice it almost always returns
        //         false and we fall through to step 3.
        if super.performKeyEquivalent(with: event) {
            return true
        }

        // Step 3: Cmd+letter synthesis fallback.
        //         Cocoa does NOT naturally deliver Cmd+letter events to
        //         keyDown, so this branch synthesizes <D-letter> / <D-1> /
        //         <S-D-}> etc. for any Cmd+ event that no menu claimed.
        //         This is how Cmd+P, Cmd+J, and any unbound Cmd+letter
        //         reach nvim today (previously via the fall-through after
        //         the systemKeys whitelist), and also how disabled default
        //         keymaps reach nvim when bind_default_keymaps = false.
        //
        //         Exception: Cmd+` is left alone so macOS's built-in
        //         Window menu cycling (auto-injected via the xib's
        //         `systemMenu="window"` attribute) can handle it through
        //         whatever path it normally does. This preserves current
        //         cycle_window behavior, which is explicitly out of scope
        //         for this iteration per the spec.
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers,
           !chars.isEmpty,
           chars != "`"
        {
            let nvimKey = KeyUtils.nvimKey(
                characters: chars, modifiers: event.modifierFlags)
            Task { await channel?.send(key: nvimKey) }
            return true
        }

        // Step 4: non-Cmd events fall through. Ctrl+Tab, F-keys, arrow
        //         keys, etc. become regular keyDown: calls in the next
        //         event dispatch stage.
        return false
    }
```

- [ ] **Step 2: Build**

Run: `make build`
Expected: build succeeds.

- [ ] **Step 3: Run unit tests**

Run: `make test`
Expected: all `ShortcutSpecTests` still pass. Existing `KeyUtilsTests` also pass (we haven't touched `KeyUtils`).

- [ ] **Step 4: Manual smoke test**

Run: `make install && open -a Veil`
Expected with default config (no `veil.toml` changes):
- Cmd+N opens new window
- Cmd+S saves (executes `:w`)
- Cmd+Z undoes
- Cmd+1 switches to first tab
- Ctrl+Tab cycles tabs
- Shift+Cmd+] cycles tabs forward
- Cmd+P (no binding in nvim by default) — either does nothing or maps to whatever the user has mapped `<D-p>` to

- [ ] **Step 5: Commit**

```bash
git add Veil/Rendering/NvimView+Keyboard.swift
git commit -m "Rewrite performKeyEquivalent as config-driven three-step dispatch"
```

### Task 18: Manual verification of `bind_default_keymaps = false`

**Files:**
- None (manual test)

- [ ] **Step 1: Edit veil.toml to disable default keymaps**

```toml
[keys]
bind_default_keymaps = false
```

- [ ] **Step 2: Relaunch Veil**

Run: `make install && open -a Veil`

- [ ] **Step 3: Verify behavior**

- File menu: Save, Close Tab items are visible. Save should have no shortcut displayed (confirm by inspecting the File menu).
- Edit menu: Undo, Redo, Cut, Copy, Paste, Select All items are visible, all without shortcut displays.
- Pressing Cmd+S: nvim receives `<D-s>`. To verify: in nvim, run `:map <D-s>` — you should see "No mapping found". Alternatively, set up a quick test mapping: `:nnoremap <D-s> :echo "got D-s"<CR>` in nvim, then press Cmd+S in Veil, the echo should appear.
- Pressing Cmd+1: nvim receives `<D-1>`, not a `:tabnext 1`.
- Pressing Ctrl+Tab: nvim receives `<C-Tab>`.
- Pressing Shift+Cmd+]: nvim receives `<S-D-}>`.
- Pressing Cmd+N: STILL opens a new window (it's a Veil-owned action, not a default keymap).
- Pressing Cmd+Q: STILL quits Veil.

- [ ] **Step 4: Restore config and verify round-trip**

Remove the `[keys]` section or set `bind_default_keymaps = true`. Relaunch. Confirm all default behavior is restored.

- [ ] **Step 5: No commit (manual verification only)**

---

## Phase 5: Documentation

### Task 19: `veil.sample.toml` update

**Files:**
- Modify: `veil.sample.toml`

- [ ] **Step 1: Add a commented `[keys]` section**

Append to `veil.sample.toml`:

```toml

# Keyboard shortcuts. See KEYBOARD.md for full documentation.

# [keys]
# When true (default), Veil binds a set of Vim-friendly default keymaps:
# Cmd+S → :w, Cmd+Z → u, Cmd+1-9 → switch tab, Ctrl+Tab → gt, etc.
# Set to false to let these keys pass through to Neovim as <D-s>, <D-1>,
# <C-Tab>, etc. You can then map them yourself in your nvim config.
# bind_default_keymaps = true

# Rebind Veil's GUI actions. Set to "" to disable a shortcut
# (the menu item remains and stays clickable).
# new_window = "cmd+n"
# new_window_with_profile = "cmd+shift+n"
# close_tab = "cmd+w"
# close_window = "cmd+shift+w"
# quit = "cmd+q"
# hide = "cmd+h"
# minimize = "cmd+m"
# toggle_fullscreen = "cmd+ctrl+f"
# open_settings = "cmd+,"
# connect_remote = "cmd+ctrl+shift+n"
```

- [ ] **Step 2: Commit**

```bash
git add veil.sample.toml
git commit -m "Add keys section to veil.sample.toml"
```

### Task 20: KEYBOARD.md

**Files:**
- Create: `KEYBOARD.md`

- [ ] **Step 1: Create KEYBOARD.md with six sections**

Write `KEYBOARD.md`:

```markdown
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

| Shortcut       | Default action (nvim command) | As sent to nvim when disabled |
| -------------- | ----------------------------- | ----------------------------- |
| `cmd+s`        | `:w`                          | `<D-s>`                       |
| `cmd+z`        | `u`                           | `<D-z>`                       |
| `cmd+shift+z`  | `<C-r>`                       | `<S-D-z>`                     |
| `cmd+c`        | `"+y`                         | `<D-c>`                       |
| `cmd+x`        | `"+d`                         | `<D-x>`                       |
| `cmd+v`        | `nvim_paste` RPC              | `<D-v>`                       |
| `cmd+a`        | `ggVG`                        | `<D-a>`                       |
| `cmd+1` … `cmd+8` | `:tabnext N`               | `<D-1>` … `<D-8>`             |
| `cmd+9`        | `:tablast`                    | `<D-9>`                       |
| `ctrl+tab`     | `:tabnext`                    | `<C-Tab>`                     |
| `shift+ctrl+tab` | `:tabprevious`              | `<C-S-Tab>`                   |
| `shift+cmd+}`  | `:tabnext`                    | `<S-D-}>`                     |
| `shift+cmd+{`  | `:tabprevious`                | `<S-D-{>`                     |

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
```

- [ ] **Step 2: Commit**

```bash
git add KEYBOARD.md
git commit -m "Add KEYBOARD.md documenting keyboard configuration"
```

### Task 21: README.md update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the "Full key passthrough" feature line**

Find the existing `Full key passthrough` bullet (introduced earlier in this session). Replace with:

```markdown
- **Full key passthrough**: every Ctrl, Option, function key, and any Cmd combination not claimed by Veil reaches Neovim directly. As a native app instead of a terminal process, you gain a rich Cmd+ mapping space that terminal setups can't offer. All default shortcuts are configurable — see [KEYBOARD.md](KEYBOARD.md).
```

- [ ] **Step 2: Simplify the Keyboard section**

Find the `### Keyboard` section (around lines 89-122 of README.md). Replace the big shortcut table with a short summary and a pointer:

```markdown
### Keyboard

Veil handles a small set of Cmd-key shortcuts for window and tab management; everything else is passed to Neovim as `<D-...>` or `<C-...>`. All shortcuts are configurable via `veil.toml` — see [KEYBOARD.md](KEYBOARD.md) for the full list, string format, and migration guide.

Quick reference:

| Key                   | Action                                |
| --------------------- | ------------------------------------- |
| `Cmd+N`               | New window                            |
| `Cmd+W`               | Close tab (or window if only one tab) |
| `` Cmd+` ``           | Cycle windows                         |
| `Cmd+1` – `Cmd+9`     | Switch tab                            |
| `Cmd+,`               | Open settings (veil.toml)             |
| `Cmd+Ctrl+Shift+N`    | Connect to remote nvim                |

For custom Cmd-key mappings in your nvim config:

\```lua
-- Example: Cmd+P to open a file picker
vim.keymap.set('n', '<D-p>', Snacks.picker.files)
\```
```

Note: replace the triple backticks in the lua block with actual backticks (they're escaped here to be embedded in this plan document).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Point README keyboard section at KEYBOARD.md"
```

---

## Phase 6: Final Verification

### Task 22: Full test suite run

**Files:**
- None

- [ ] **Step 1: Run the full test suite**

Run: `make test`
Expected: all VeilTests pass, including new `ShortcutSpecTests` and existing `KeyUtilsTests`, `GridTests`, etc.

- [ ] **Step 2: Build in Release mode**

Run: `make build`
Expected: clean Release build with no warnings from the new code.

### Task 23: Manual smoke test matrix

**Files:**
- None

- [ ] **Step 1: With default config (no `[keys]` section)**

Verify: all existing keyboard behavior unchanged. Test Cmd+N, Cmd+W, Cmd+S, Cmd+Z, Cmd+Shift+Z, Cmd+1, Ctrl+Tab, Shift+Cmd+], Cmd+Q, Cmd+M, Cmd+Ctrl+F, Cmd+Shift+N, Cmd+Ctrl+Shift+N.

- [ ] **Step 2: With `bind_default_keymaps = false`**

Verify: Veil-owned actions (Cmd+N, Cmd+W, Cmd+Q, etc.) still work. Cmd+S no longer saves (sends `<D-s>` to nvim). Cmd+1 no longer switches tab (sends `<D-1>`). Ctrl+Tab no longer cycles (sends `<C-Tab>`). Shift+Cmd+] no longer cycles (sends `<S-D-}>`).

Test with a trivial nvim mapping to confirm: `:nnoremap <D-s> :echo "D-s received"<CR>`.

- [ ] **Step 3: With a rebound action**

Set `new_window = "cmd+alt+n"`. Verify File menu displays `⌥⌘N`, the shortcut opens a new window, and `⌘N` no longer does.

- [ ] **Step 4: With a disabled action**

Set `quit = ""`. Verify App menu's Quit item has no shortcut display but remains clickable (clicking it quits Veil).

- [ ] **Step 5: With a malformed shortcut**

Set `new_window = "cmd+nope+n"`. Relaunch Veil. Verify:
- stderr / Console.app shows an `NSLog` warning about the malformed shortcut
- File menu's "New" item has no shortcut displayed (treated as disabled)
- Other actions still work normally

---

## Out of Scope (for reference)

See the spec for rationale. These are explicitly NOT part of this plan:

- Settings UI
- Shortcut conflict detection
- Live config reload
- Chord / multi-stage shortcuts
- Rebinding Cmd+\` (cycle_window) — stays as macOS system behavior
- User-defined custom nvim command actions

## Summary of Commits

Expected final commit graph (23 commits total across the phases):

1. Add ShortcutSpec data types
2. Add failing modifier parsing tests
3. Implement modifier + single-char parsing
4. Add named key parsing tests
5. Add parser error case tests
6. Implement matches for single-char + flag stripping
7. Implement named key matching
8. Implement toMenuKeyEquivalent
9. Add KeyAction enum with defaults
10. Add KeysConfig decoding
11. Add KeysConfig integration tests
12. Add findMenuItem helper
13. Add applyConfiguredKeyEquivalents pass
14. Wire the pass into startup
15. (manual verification, no commit)
16. Add non-menu default keymap dispatch table
17. Rewrite performKeyEquivalent
18. (manual verification, no commit)
19. Add [keys] section to veil.sample.toml
20. Add KEYBOARD.md
21. Update README keyboard section
22. (final test run, no commit)
23. (final smoke test, no commit)

Tasks 15, 18, 22, 23 are verification steps without commits — so 19 actual commits.
