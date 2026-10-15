import AppKit
import Metal
import Testing
@testable import Veil

@MainActor
final class GlyphAtlasTests {

    let atlas: GlyphAtlas
    let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let cellSize = CGSize(width: 8, height: 16)

    /// Cells of a group too wide for one row of a 256-pixel atlas at 2x.
    let wideGroupCells = 40

    init() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        atlas = GlyphAtlas(device: device, size: 256)
        atlas.scale = 2
    }

    private var wideGroup: String { String(repeating: "-", count: wideGroupCells) }

    @Test func aRegionNeverExtendsPastTheTexture() {
        let region = atlas.region(
            text: wideGroup, font: font, bold: false, italic: false,
            cellSize: cellSize, cellCount: wideGroupCells)
        #expect(region.u >= 0)
        #expect(region.uMax <= 1)
    }

    @Test func aGroupWiderThanTheAtlasIsStoredInSegmentsCoveringEveryCell() {
        let segments = atlas.segments(
            text: wideGroup, font: font, bold: false, italic: false,
            cellSize: cellSize, cellCount: wideGroupCells)

        #expect(segments.count > 1)
        var nextCell = 0
        for segment in segments {
            #expect(segment.colOffset == nextCell)
            #expect(segment.region.uMax <= 1)
            #expect(segment.region.drawWidth == Float(cellSize.width) * Float(segment.cellCount))
            nextCell += segment.cellCount
        }
        #expect(nextCell == wideGroupCells)
    }

    @Test func aGroupIsFittedToTheWidthOfItsCells() {
        // Natural advance of the system monospace font at 14pt is wider than
        // the 8-point cell, as a rounded grid often is.
        let segments = atlas.segments(
            text: "->", font: font, bold: false, italic: false,
            cellSize: cellSize, cellCount: 2)
        #expect(segments.count == 1)
        #expect(segments.first?.region.drawWidth == Float(cellSize.width) * 2)
    }
}
