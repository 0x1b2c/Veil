import CoreText

/// Resolves font fallback for characters missing from the primary font.
///
/// CoreText's `CTFontCreateForString` handles most fallback (e.g. CJK → PingFang),
/// but returns LastResort for BMP Private Use Area characters (U+E000-U+F8FF) even
/// when an installed Nerd Font covers them. To work around this, we probe for a
/// Nerd Font at startup using supplementary PUA characters (which CoreText handles
/// correctly), then use the discovered font for BMP PUA fallback.
nonisolated enum FontFallback {
    nonisolated(unsafe) private(set) static var nerdFontName: String?

    /// Cache of primary-family → CJK-variant-family lookups. An empty string
    /// means "searched, no variant found" so we skip the expensive scan on
    /// subsequent calls.
    nonisolated(unsafe) private static var cjkVariantCache: [String: String] = [:]

    /// Probe for an installed Nerd Font by trying supplementary PUA characters
    /// from niche to popular. A font that covers niche characters is more likely
    /// to be a comprehensive Nerd Font with full icon coverage.
    static func probe() {
        if nerdFontName != nil { return }
        let probe = CTFontCreateWithName(
            ".AppleSystemUIFontMonospaced-Regular" as CFString, 16, nil)
        let probeChars: [Character] = [
            "\u{F1064}",  // 󱁤 nf-md-expand_all (deep supplementary PUA)
            "\u{F0A19}",  // 󰨙 nf-md-star (mid-range supplementary PUA)
            "\u{F0001}",  // 󰀁 nf-md-ab_testing (early supplementary PUA)
        ]
        for ch in probeChars {
            let text = String(ch)
            let fallback = CTFontCreateForString(
                probe, text as CFString,
                CFRange(location: 0, length: text.utf16.count))
            let name = CTFontCopyPostScriptName(fallback) as String
            if name != "LastResort" {
                nerdFontName = name
                return
            }
        }
    }

    /// Returns a font suitable for rendering the given text. If the provided font
    /// lacks glyphs, falls back to a system font or the probed Nerd Font.
    /// The fallback font is re-sized so its cap height matches the primary
    /// font's, preventing the visual "small Chinese next to big English"
    /// mismatch that appears when fallback metrics differ from the primary.
    static func resolveFont(_ font: CTFont, for text: String) -> CTFont {
        let utf16 = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        if CTFontGetGlyphsForCharacters(font, utf16, &glyphs, utf16.count) {
            return font
        }
        // Look for a same-family CJK variant (e.g. "Maple Mono NF" →
        // "Maple Mono NF CN") before handing off to the system fallback.
        // Family-matched variants preserve the primary font's design
        // language, avoiding the visual mismatch that appears when
        // CoreText picks an unrelated fallback such as PingFang SC.
        if let variant = findFamilyCJKVariant(of: font, utf16: utf16) {
            return scaleToPrimaryCapHeight(variant, primary: font)
        }
        let fallback = CTFontCreateForString(
            font, text as CFString,
            CFRange(location: 0, length: utf16.count))
        let fallbackName = CTFontCopyPostScriptName(fallback) as String
        if fallbackName != "LastResort" {
            return scaleToPrimaryCapHeight(fallback, primary: font)
        }
        if let cachedName = nerdFontName {
            let nerd = CTFontCreateWithName(cachedName as CFString, CTFontGetSize(font), nil)
            return scaleToPrimaryCapHeight(nerd, primary: font)
        }
        return fallback
    }

    /// Try common CJK suffixes (" CN", " SC", " TC", " JP", " KR", " HK")
    /// on the primary font's family name. A family is considered a match
    /// only if CoreText returns a font whose family name exactly equals the
    /// requested name AND that font actually contains glyphs for the text.
    /// Results are cached per primary-family name to avoid re-scanning on
    /// every glyph.
    private static func findFamilyCJKVariant(of primary: CTFont, utf16: [UInt16]) -> CTFont? {
        let familyName = CTFontCopyFamilyName(primary) as String
        let size = CTFontGetSize(primary)

        if let cached = cjkVariantCache[familyName] {
            guard !cached.isEmpty else { return nil }
            return resolvedCJKFont(name: cached, size: size, utf16: utf16)
        }

        let suffixes = [" CN", " SC", " TC", " JP", " KR", " HK"]
        for suffix in suffixes {
            let candidateName = familyName + suffix
            let candidate = CTFontCreateWithName(candidateName as CFString, size, nil)
            let actualName = CTFontCopyFamilyName(candidate) as String
            // CoreText returns a substitute font when the requested name
            // doesn't exist; verify the result actually matches.
            guard actualName == candidateName else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
            if CTFontGetGlyphsForCharacters(candidate, utf16, &glyphs, utf16.count) {
                cjkVariantCache[familyName] = candidateName
                return candidate
            }
        }

        cjkVariantCache[familyName] = ""
        return nil
    }

    private static func resolvedCJKFont(name: String, size: CGFloat, utf16: [UInt16]) -> CTFont? {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(font, utf16, &glyphs, utf16.count) else {
            return nil
        }
        return font
    }

    /// Rescale `fallback` so its cap height matches the primary font's.
    /// Mirrors Ghostty's `scaleFactor` using cap height as the normalization
    /// metric (Ghostty's preferred chain is ic_width → ex_height → cap_height
    /// → line_height; starting with cap_height is sufficient for most cases).
    private static func scaleToPrimaryCapHeight(_ fallback: CTFont, primary: CTFont) -> CTFont {
        let primaryCapHeight = CTFontGetCapHeight(primary)
        let fallbackCapHeight = CTFontGetCapHeight(fallback)
        guard primaryCapHeight > 0, fallbackCapHeight > 0,
            primaryCapHeight != fallbackCapHeight
        else { return fallback }
        let scale = primaryCapHeight / fallbackCapHeight
        let targetSize = CTFontGetSize(primary) * scale
        let descriptor = CTFontCopyFontDescriptor(fallback)
        return CTFontCreateWithFontDescriptor(descriptor, targetSize, nil)
    }
}
