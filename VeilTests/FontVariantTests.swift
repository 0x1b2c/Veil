import AppKit
import Testing
@testable import Veil

struct FontVariantTests {

    /// Menlo ships with macOS in all four styles, so the traits each
    /// variant resolves to do not depend on what the user has installed.
    let font = NSFont(name: "Menlo-Regular", size: 14)!

    private func traits(_ font: NSFont) -> NSFontDescriptor.SymbolicTraits {
        font.fontDescriptor.symbolicTraits
    }

    @Test func boldItalicResolvesToAFaceThatIsBothBoldAndItalic() {
        let variant = fontVariant(font, bold: true, italic: true)
        #expect(traits(variant).contains(.bold))
        #expect(traits(variant).contains(.italic))
    }

    @Test func boldAloneStaysUpright() {
        let variant = fontVariant(font, bold: true, italic: false)
        #expect(traits(variant).contains(.bold))
        #expect(!traits(variant).contains(.italic))
    }

    @Test func italicAloneStaysRegularWeight() {
        let variant = fontVariant(font, bold: false, italic: true)
        #expect(!traits(variant).contains(.bold))
        #expect(traits(variant).contains(.italic))
    }

    @Test func plainTextKeepsTheGridFont() {
        #expect(fontVariant(font, bold: false, italic: false) == font)
    }
}
