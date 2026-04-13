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
}
