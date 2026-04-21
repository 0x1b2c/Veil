import XCTest
@testable import Veil

final class GlyphCacheTests: XCTestCase {
    private var cache: GlyphCache!
    private let defaultFg = 0x000000
    private let defaultBg = 0xFFFFFF

    override func setUp() {
        super.setUp()
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let cellSize = CGSize(width: 8, height: 16)
        cache = GlyphCache(font: font, cellSize: cellSize)
    }

    override func tearDown() {
        cache = nil
        super.tearDown()
    }

    func testCacheMissRendersNonNilImage() {
        let attrs = CellAttributes()
        let glyph = cache.get(text: "A", attrs: attrs, defaultFg: defaultFg, defaultBg: defaultBg)
        XCTAssertGreaterThan(glyph.image.width, 0)
        XCTAssertGreaterThan(glyph.image.height, 0)
    }

    func testCacheHitReturnsSameObject() {
        let attrs = CellAttributes()
        let glyph1 = cache.get(text: "B", attrs: attrs, defaultFg: defaultFg, defaultBg: defaultBg)
        let glyph2 = cache.get(text: "B", attrs: attrs, defaultFg: defaultFg, defaultBg: defaultBg)
        XCTAssertTrue(
            glyph1.image === glyph2.image, "Cache hit should return the same CGImage instance")
    }

    func testDifferentAttributesProduceDifferentImages() {
        let attrs1 = CellAttributes()
        let attrs2 = CellAttributes(bold: true)
        let glyph1 = cache.get(text: "C", attrs: attrs1, defaultFg: defaultFg, defaultBg: defaultBg)
        let glyph2 = cache.get(text: "C", attrs: attrs2, defaultFg: defaultFg, defaultBg: defaultBg)
        XCTAssertFalse(
            glyph1.image === glyph2.image,
            "Different attributes should produce different cached images")
    }

    func testInvalidateClearsCache() {
        let attrs = CellAttributes()
        let glyph1 = cache.get(text: "D", attrs: attrs, defaultFg: defaultFg, defaultBg: defaultBg)
        cache.invalidate()
        let glyph2 = cache.get(text: "D", attrs: attrs, defaultFg: defaultFg, defaultBg: defaultBg)
        XCTAssertFalse(
            glyph1.image === glyph2.image,
            "After invalidation, a new image should be rendered")
    }
}
