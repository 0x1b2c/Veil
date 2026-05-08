import AppKit
import XCTest
@testable import Veil

final class ShortcutTests: XCTestCase {

    // MARK: - Parse: modifiers

    func testParseSingleModifierCmd() {
        let spec = Shortcut.parse("cmd+n")
        XCTAssertEqual(spec?.modifiers, .command)
        XCTAssertEqual(spec?.key, .character("n"))
    }

    func testParseSingleModifierCtrl() {
        let spec = Shortcut.parse("ctrl+a")
        XCTAssertEqual(spec?.modifiers, .control)
        XCTAssertEqual(spec?.key, .character("a"))
    }

    func testParseSingleModifierShift() {
        let spec = Shortcut.parse("shift+a")
        XCTAssertEqual(spec?.modifiers, .shift)
        XCTAssertEqual(spec?.key, .character("a"))
    }

    func testParseSingleModifierAlt() {
        let spec = Shortcut.parse("alt+a")
        XCTAssertEqual(spec?.modifiers, .option)
        XCTAssertEqual(spec?.key, .character("a"))
    }

    func testParseOptionAliasForAlt() {
        let spec = Shortcut.parse("option+a")
        XCTAssertEqual(spec?.modifiers, .option)
    }

    func testParseMultipleModifiers() {
        let spec = Shortcut.parse("cmd+shift+n")
        XCTAssertEqual(spec?.modifiers, [.command, .shift])
        XCTAssertEqual(spec?.key, .character("n"))
    }

    func testParseAllFourModifiers() {
        let spec = Shortcut.parse("cmd+ctrl+shift+alt+n")
        XCTAssertEqual(spec?.modifiers, [.command, .control, .shift, .option])
    }

    func testParseModifiersCaseInsensitive() {
        XCTAssertEqual(Shortcut.parse("CMD+N")?.modifiers, .command)
        XCTAssertEqual(Shortcut.parse("Cmd+N")?.modifiers, .command)
    }

    func testParseWhitespaceTolerance() {
        let spec = Shortcut.parse("cmd + shift + n")
        XCTAssertEqual(spec?.modifiers, [.command, .shift])
        XCTAssertEqual(spec?.key, .character("n"))
    }

    // MARK: - Parse: named keys

    func testParseNamedKeyTab() {
        let spec = Shortcut.parse("cmd+tab")
        XCTAssertEqual(spec?.modifiers, .command)
        XCTAssertEqual(spec?.key, .named(.tab))
    }

    func testParseNamedKeyReturn() {
        XCTAssertEqual(Shortcut.parse("return")?.key, .named(.return))
    }

    func testParseNamedKeyEscape() {
        XCTAssertEqual(Shortcut.parse("escape")?.key, .named(.escape))
    }

    func testParseNamedKeyArrows() {
        XCTAssertEqual(Shortcut.parse("up")?.key, .named(.up))
        XCTAssertEqual(Shortcut.parse("down")?.key, .named(.down))
        XCTAssertEqual(Shortcut.parse("left")?.key, .named(.left))
        XCTAssertEqual(Shortcut.parse("right")?.key, .named(.right))
    }

    func testParseNamedKeyPageUp() {
        XCTAssertEqual(Shortcut.parse("pageup")?.key, .named(.pageUp))
    }

    func testParseNamedKeyF5() {
        XCTAssertEqual(Shortcut.parse("f5")?.key, .named(.f5))
    }

    func testParseNamedKeyF20() {
        XCTAssertEqual(Shortcut.parse("f20")?.key, .named(.f20))
    }

    func testParseNamedKeyF35() {
        XCTAssertEqual(Shortcut.parse("f35")?.key, .named(.f35))
    }

    func testParseNamedKeyInsert() {
        XCTAssertEqual(Shortcut.parse("insert")?.key, .named(.insert))
    }

    func testParseNamedKeyCaseInsensitive() {
        XCTAssertEqual(Shortcut.parse("Tab")?.key, .named(.tab))
        XCTAssertEqual(Shortcut.parse("PAGEUP")?.key, .named(.pageUp))
        XCTAssertEqual(Shortcut.parse("F5")?.key, .named(.f5))
    }

    // MARK: - Parse: error cases

    func testParseEmptyStringReturnsNil() {
        XCTAssertNil(Shortcut.parse(""))
    }

    func testParseWhitespaceOnlyReturnsNil() {
        XCTAssertNil(Shortcut.parse("   "))
    }

    func testParseNoKeyReturnsNil() {
        XCTAssertNil(Shortcut.parse("cmd+shift"))
    }

    func testParseOnlyModifierShiftReturnsNil() {
        XCTAssertNil(Shortcut.parse("shift"))
    }

    func testParseOnlyModifierCmdReturnsNil() {
        XCTAssertNil(Shortcut.parse("cmd"))
    }

    func testParseMultipleKeysReturnsNil() {
        XCTAssertNil(Shortcut.parse("cmd+a+b"))
    }

    func testParseMultiCharKeyWithoutNamedMatchReturnsNil() {
        XCTAssertNil(Shortcut.parse("cmd+nope"))
    }

    func testParseConsecutivePlusParsesAsNormal() {
        // Swift's split(separator:) defaults to omittingEmptySubsequences: true,
        // so "cmd++n" parses the same as "cmd+n". Documenting this behavior.
        let spec = Shortcut.parse("cmd++n")
        XCTAssertEqual(spec?.modifiers, .command)
        XCTAssertEqual(spec?.key, .character("n"))
    }

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
        let spec = Shortcut.parse("cmd+s")!
        let event = makeKeyDown(chars: "s", modifiers: .command)
        XCTAssertTrue(spec.matches(event))
    }

    func testDoesNotMatchWhenModifiersDiffer() {
        let spec = Shortcut.parse("cmd+s")!
        let event = makeKeyDown(chars: "s", modifiers: .control)
        XCTAssertFalse(spec.matches(event))
    }

    func testMatchesCaseInsensitive() {
        // Spec parsed as lowercase "a", but event has uppercase "A"
        let spec = Shortcut.parse("cmd+a")!
        let event = makeKeyDown(chars: "A", modifiers: .command)
        XCTAssertTrue(spec.matches(event))
    }

    // MARK: - Matches: modifier flag stripping

    func testMatchesIgnoresFunctionFlag() {
        // F5 events have .function set automatically
        let spec = Shortcut.parse("f5")!
        let event = makeKeyDown(
            chars: String(Character(UnicodeScalar(NSF5FunctionKey)!)),
            modifiers: .function,
            keyCode: 96)
        XCTAssertTrue(spec.matches(event))
    }

    func testMatchesIgnoresNumericPadFlag() {
        let spec = Shortcut.parse("up")!
        let event = makeKeyDown(
            chars: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)),
            modifiers: [.function, .numericPad],
            keyCode: 126)
        XCTAssertTrue(spec.matches(event))
    }

    func testMatchesIgnoresCapsLock() {
        let spec = Shortcut.parse("cmd+s")!
        let event = makeKeyDown(chars: "s", modifiers: [.command, .capsLock])
        XCTAssertTrue(spec.matches(event))
    }

    // MARK: - Matches: shifted punctuation

    func testMatchesShiftedPunctuationCloseBrace() {
        // Shift+Cmd+] produces charactersIgnoringModifiers == "}"
        let spec = Shortcut.parse("shift+cmd+}")!
        let event = makeKeyDown(
            chars: "}",
            charsIgnoringMods: "}",
            modifiers: [.shift, .command])
        XCTAssertTrue(spec.matches(event))
    }

    /// The shifted-punctuation workaround: users can write either side of the
    /// pair and match the same physical key. `shift+cmd+]` should match the
    /// event even though Cocoa delivered "}" in `charactersIgnoringModifiers`.
    func testMatchesUnshiftedFormOfShiftedPunctuation() {
        let spec = Shortcut.parse("shift+cmd+]")!
        let event = makeKeyDown(
            chars: "}",
            charsIgnoringMods: "}",
            modifiers: [.shift, .command])
        XCTAssertTrue(spec.matches(event))
    }

    func testMatchesUnshiftedOpenBracket() {
        let spec = Shortcut.parse("shift+cmd+[")!
        let event = makeKeyDown(
            chars: "{",
            charsIgnoringMods: "{",
            modifiers: [.shift, .command])
        XCTAssertTrue(spec.matches(event))
    }

    func testMatchesUnshiftedDigit() {
        // Shift+Cmd+1 produces charactersIgnoringModifiers == "!" on US layout.
        // User writing `shift+cmd+1` should match that.
        let spec = Shortcut.parse("shift+cmd+1")!
        let event = makeKeyDown(
            chars: "!",
            charsIgnoringMods: "!",
            modifiers: [.shift, .command])
        XCTAssertTrue(spec.matches(event))
    }

    func testShiftedPunctuationRequiresShiftModifier() {
        // Without shift in the spec, the workaround should NOT kick in.
        // `cmd+]` must not match an event with "}" (which can't physically
        // happen without shift, but we defend the logic anyway).
        let spec = Shortcut.parse("cmd+]")!
        let event = makeKeyDown(
            chars: "}",
            charsIgnoringMods: "}",
            modifiers: .command)
        XCTAssertFalse(spec.matches(event))
    }

    // MARK: - Matches: named keys

    func testMatchesF35() {
        let spec = Shortcut.parse("f35")!
        let event = makeKeyDown(
            chars: String(Character(UnicodeScalar(NSF1FunctionKey + 34)!)),
            modifiers: .function,
            keyCode: 0)
        XCTAssertTrue(spec.matches(event))
    }

    func testMatchesInsert() {
        let spec = Shortcut.parse("insert")!
        let event = makeKeyDown(
            chars: String(Character(UnicodeScalar(NSInsertFunctionKey)!)),
            modifiers: .function,
            keyCode: 0)
        XCTAssertTrue(spec.matches(event))
    }

    // MARK: - toMenuKeyEquivalent

    func testMenuEquivalentSimpleLetter() {
        let (key, mask) = Shortcut.parse("cmd+n")!.toMenuKeyEquivalent()!
        XCTAssertEqual(key, "n")
        XCTAssertEqual(mask, .command)
    }

    func testMenuEquivalentShiftLetterUsesUppercase() {
        let (key, mask) = Shortcut.parse("cmd+shift+n")!.toMenuKeyEquivalent()!
        XCTAssertEqual(key, "N")
        XCTAssertEqual(mask, [.command, .shift])
    }

    func testMenuEquivalentShiftPunctuationPassthrough() {
        let (key, mask) = Shortcut.parse("cmd+shift+}")!.toMenuKeyEquivalent()!
        XCTAssertEqual(key, "}")
        XCTAssertEqual(mask, [.command, .shift])
    }

    func testMenuEquivalentDigitPassthrough() {
        let (key, mask) = Shortcut.parse("cmd+1")!.toMenuKeyEquivalent()!
        XCTAssertEqual(key, "1")
        XCTAssertEqual(mask, .command)
    }

    func testMenuEquivalentComma() {
        let (key, mask) = Shortcut.parse("cmd+,")!.toMenuKeyEquivalent()!
        XCTAssertEqual(key, ",")
        XCTAssertEqual(mask, .command)
    }

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
                Shortcut.parse(action.defaultShortcut),
                "Default shortcut '\(action.defaultShortcut)' for \(action.rawValue) failed to parse"
            )
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
}
