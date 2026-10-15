import AppKit
import Foundation
import Metal
import QuartzCore
import Testing
@testable import Veil

@MainActor
final class MetalRendererTests {

    let renderer: MetalRenderer
    let atlas: GlyphAtlas
    let grid: Grid
    let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let cellSize = CGSize(width: 8, height: 16)

    /// Vertices of the cursor quad, which every presented frame contains.
    let cursorVertexCount = 6

    init() throws {
        renderer = try MetalRenderer()
        atlas = GlyphAtlas(device: renderer.device)
        grid = Grid()
        grid.resize(width: 5, height: 3)
        grid.putCells(
            row: 1, colStart: 0,
            data: [
                GridCellData(text: "H", hlId: 0, repeats: 1),
                GridCellData(text: "i", hlId: 0, repeats: 1),
            ])
    }

    /// A layer with a device and a non-zero size, so it can vend drawables.
    private func drawableLayer() -> CAMetalLayer {
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.drawableSize = CGSize(width: 80, height: 64)
        return layer
    }

    /// A layer without a device, whose nextDrawable() returns nil the way it
    /// does when every drawable is still held by the compositor.
    private func layerWithoutDrawables() -> CAMetalLayer {
        CAMetalLayer()
    }

    @discardableResult
    private func render(
        dirtyRows: IndexSet, in layer: CAMetalLayer, atlas: GlyphAtlas? = nil,
        font: NSFont? = nil, cellSize: CGSize? = nil
    ) -> Bool {
        renderer.render(
            cells: grid.cells, attributes: grid.attributes,
            rows: grid.size.rows, cols: grid.size.cols,
            dirtyRows: dirtyRows,
            atlas: atlas ?? self.atlas, font: font ?? self.font,
            cellSize: cellSize ?? self.cellSize,
            gridTopPadding: 0, defaultFg: 0xFFFFFF, defaultBg: 0x000000,
            cursorPosition: Position(row: 0, col: 0), cursorShape: .block,
            cursorCellPercentage: 100,
            debugOverlay: nil,
            in: layer)
    }

    @Test func rowsDirtyInAFrameWithoutDrawableAreDrawnInTheNextFrame() {
        render(dirtyRows: grid.dirtyRows, in: layerWithoutDrawables())
        render(dirtyRows: IndexSet(), in: drawableLayer())
        #expect(renderer.lastVertexCount > cursorVertexCount)
    }

    @Test func frameWithoutDrawableIsReportedAsNotPresented() {
        #expect(!render(dirtyRows: grid.dirtyRows, in: layerWithoutDrawables()))
        #expect(render(dirtyRows: IndexSet(), in: drawableLayer()))
    }

    // MARK: - Atlas changes

    private func put(_ text: String, row: Int) {
        grid.putCells(
            row: row, colStart: 0,
            data: text.map { GridCellData(text: String($0), hlId: 0, repeats: 1) })
    }

    /// The atlas region the glyph "H" of row 1 must sample from right now.
    private func currentRegionOfH(in atlas: GlyphAtlas) -> GlyphAtlas.Region {
        atlas.region(
            text: "H", font: font, bold: false, italic: false, cellSize: cellSize)
    }

    /// Texture coordinates of the bottom-left corner of the first glyph quad
    /// in the row: the corner whose v changes when the atlas grows.
    private func bottomLeftTexCoordOfFirstGlyph(inRow row: Int) -> SIMD2<Float>? {
        let vertices = renderer.rowForegroundVertices[row]
        return vertices.count > 2 ? vertices[2].texCoord : nil
    }

    /// An atlas with room for only a handful of glyphs, so a few new ones grow it.
    private func smallAtlas() -> GlyphAtlas {
        GlyphAtlas(device: renderer.device, size: 64)
    }

    @Test func rowsCachedBeforeAtlasGrowthSampleTheGrownAtlas() {
        let atlas = smallAtlas()
        render(dirtyRows: grid.dirtyRows, in: drawableLayer(), atlas: atlas)
        let heightBefore = atlas.atlasHeight

        put("ABCDE", row: 0)
        put("FGHIJ", row: 2)
        render(dirtyRows: IndexSet([0, 2]), in: drawableLayer(), atlas: atlas)

        #expect(atlas.atlasHeight > heightBefore)
        let region = currentRegionOfH(in: atlas)
        #expect(bottomLeftTexCoordOfFirstGlyph(inRow: 1) == SIMD2(region.u, region.vMax))
    }

    @Test func rowsRebuiltEarlierInTheFrameThatGrowsTheAtlasSampleTheGrownAtlas() {
        let atlas = smallAtlas()
        put("ABCDE", row: 0)
        put("Hi", row: 1)
        put("FGIJK", row: 2)
        render(dirtyRows: IndexSet(0..<3), in: drawableLayer(), atlas: atlas)

        #expect(atlas.atlasHeight > 64)
        let region = currentRegionOfH(in: atlas)
        #expect(bottomLeftTexCoordOfFirstGlyph(inRow: 1) == SIMD2(region.u, region.vMax))
    }

    @Test func rowsAreRedrawnAfterTheAtlasIsInvalidated() {
        render(dirtyRows: grid.dirtyRows, in: drawableLayer())
        atlas.invalidate()
        render(dirtyRows: IndexSet(), in: drawableLayer())
        #expect(atlas.regionCount > 0)
    }

    @Test func rowsAreRedrawnAtTheNewScaleAfterABackingScaleChange() {
        let layer = drawableLayer()
        layer.contentsScale = 2
        atlas.scale = 2
        render(dirtyRows: grid.dirtyRows, in: layer)
        let before = currentRegionOfH(in: atlas)

        layer.contentsScale = 1
        atlas.scale = 1
        render(dirtyRows: IndexSet(), in: layer)

        // "i" is the second glyph of row 1, one cell (8 points) from the left.
        let iQuadX = renderer.rowForegroundVertices[1][6].position.x
        #expect(iQuadX == 8)
        let after = currentRegionOfH(in: atlas)
        #expect(after.uMax - after.u < before.uMax - before.u)
    }

    // MARK: - Long shaped groups

    /// A font that merges a run of hyphens into one contextual-alternates
    /// group. No system monospace font does, so this test needs the font the
    /// group was first seen with.
    static let groupingFont = NSFont(name: "MapleMono-NF-CN-Regular", size: 19)

    /// Pixels of the atlas texture under a quad's texture coordinates.
    private func coverage(
        ofQuadAt index: Int, in vertices: [MetalRenderer.Vertex], atlas: GlyphAtlas
    ) -> Int {
        let texture = atlas.texture!
        let corners = vertices[index..<index + 6].map(\.texCoord)
        let x0 = Int(corners.map(\.x).min()! * Float(texture.width))
        let x1 = min(Int(corners.map(\.x).max()! * Float(texture.width)), texture.width)
        let y0 = Int(corners.map(\.y).min()! * Float(texture.height))
        let y1 = min(Int(corners.map(\.y).max()! * Float(texture.height)), texture.height)
        guard x1 > x0, y1 > y0 else { return 0 }
        var bytes = [UInt8](repeating: 0, count: (x1 - x0) * (y1 - y0))
        texture.getBytes(
            &bytes, bytesPerRow: x1 - x0,
            from: MTLRegionMake2D(x0, y0, x1 - x0, y1 - y0), mipmapLevel: 0)
        return bytes.filter { $0 > 0 }.count
    }

    @Test(.enabled(if: groupingFont != nil))
    func aHyphenRunWiderThanTheAtlasIsDrawnInsideItsCells() throws {
        let font = try #require(Self.groupingFont)
        let cellSize = CGSize(width: 11, height: 24)
        let dashes = 113
        grid.resize(width: dashes + 6, height: 3)
        put(String(repeating: "-", count: dashes) + " {{{1", row: 0)
        let layer = drawableLayer()
        layer.contentsScale = 2
        atlas.scale = 2

        render(
            dirtyRows: IndexSet(0..<3), in: layer, font: font, cellSize: cellSize)

        let cellW = Float(cellSize.width) * 2
        let vertices = renderer.rowForegroundVertices[0]
        let runQuads = stride(from: 0, to: vertices.count, by: 6).filter {
            vertices[$0].position.x < Float(dashes) * cellW
        }
        #expect(!runQuads.isEmpty)
        for quad in runQuads {
            let right = vertices[quad..<quad + 6].map(\.position.x).max()!
            #expect(right <= Float(dashes) * cellW)
            #expect(coverage(ofQuadAt: quad, in: vertices, atlas: atlas) > 0)
        }
    }
}
