import XCTest
import Carbon.HIToolbox
@testable import Veil

final class KeyUtilsTests: XCTestCase {
    func testPlainCharacter() {
        XCTAssertEqual(KeyUtils.nvimKey(characters: "a", modifiers: []), "a")
        XCTAssertEqual(KeyUtils.nvimKey(characters: "Z", modifiers: []), "Z")
    }
    func testSpecialCharactersEscaped() {
        XCTAssertEqual(KeyUtils.nvimKey(characters: "<", modifiers: []), "<lt>")
        XCTAssertEqual(KeyUtils.nvimKey(characters: "\\", modifiers: []), "<Bslash>")
    }
    func testEnterKey() {
        XCTAssertEqual(KeyUtils.nvimKey(characters: "\r", modifiers: []), "<CR>")
    }
    func testEscapeKey() {
        XCTAssertEqual(KeyUtils.nvimKey(characters: "\u{1B}", modifiers: []), "<Esc>")
    }
    func testBackspace() {
        XCTAssertEqual(KeyUtils.nvimKey(characters: "\u{7F}", modifiers: []), "<BS>")
    }
    func testTab() { XCTAssertEqual(KeyUtils.nvimKey(characters: "\t", modifiers: []), "<Tab>") }
    func testSpace() { XCTAssertEqual(KeyUtils.nvimKey(characters: " ", modifiers: []), "<Space>") }
    func testArrowKeys() {
        let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        XCTAssertEqual(KeyUtils.nvimKey(characters: up, modifiers: []), "<Up>")
        let down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        XCTAssertEqual(KeyUtils.nvimKey(characters: down, modifiers: []), "<Down>")
    }
    func testFunctionKeys() {
        let f1 = String(Character(UnicodeScalar(NSF1FunctionKey)!))
        XCTAssertEqual(KeyUtils.nvimKey(characters: f1, modifiers: []), "<F1>")
    }
    func testControlModifier() {
        XCTAssertEqual(KeyUtils.nvimKey(characters: "a", modifiers: .control), "<C-a>")
    }
    func testAltModifier() {
        XCTAssertEqual(KeyUtils.nvimKey(characters: "x", modifiers: .option), "<M-x>")
    }
    func testCmdModifier() {
        XCTAssertEqual(KeyUtils.nvimKey(characters: "s", modifiers: .command), "<D-s>")
    }
    func testMultipleModifiers() {
        XCTAssertEqual(KeyUtils.nvimKey(characters: "a", modifiers: [.control, .shift]), "<C-S-a>")
    }
    func testControlWithSpecialKey() {
        let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        XCTAssertEqual(KeyUtils.nvimKey(characters: up, modifiers: .control), "<C-Up>")
    }

    // MARK: - Shifted-punctuation reverse translation
    //
    // Cocoa delivers Shift+] as `}` in `charactersIgnoringModifiers`. KeyUtils
    // reverses that so the nvim key string reflects the physical key the user
    // pressed, letting mappings be written as `<S-D-]>` rather than `<S-D-}>`.

    func testShiftedPunctuationTranslatesToUnshifted() {
        XCTAssertEqual(
            KeyUtils.nvimKey(characters: "}", modifiers: [.command, .shift]),
            "<S-D-]>")
    }

    func testShiftedDigitTranslatesToUnshifted() {
        XCTAssertEqual(
            KeyUtils.nvimKey(characters: "@", modifiers: [.control, .shift]),
            "<C-S-2>")
    }

    func testShiftedPipeTranslatesToBslash() {
        // `|` reverse-maps to `\`, which then hits the existing Bslash branch.
        XCTAssertEqual(
            KeyUtils.nvimKey(characters: "|", modifiers: [.command, .shift]),
            "<S-D-Bslash>")
    }

    func testShiftAloneStillTranslatesPunctuation() {
        XCTAssertEqual(
            KeyUtils.nvimKey(characters: "?", modifiers: .shift),
            "<S-/>")
    }

    func testShiftedLetterIsNotTranslated() {
        // Letters are not in the punctuation pair table; translation must not
        // apply, so Shift+Cmd+A continues to produce <S-D-A>.
        XCTAssertEqual(
            KeyUtils.nvimKey(characters: "A", modifiers: [.command, .shift]),
            "<S-D-A>")
    }
}
