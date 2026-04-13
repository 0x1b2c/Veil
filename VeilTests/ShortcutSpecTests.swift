import AppKit
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
}
