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
