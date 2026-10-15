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
    private func render(dirtyRows: IndexSet, in layer: CAMetalLayer) -> Bool {
        renderer.render(
            cells: grid.cells, attributes: grid.attributes,
            rows: grid.size.rows, cols: grid.size.cols,
            dirtyRows: dirtyRows,
            atlas: atlas, font: font, cellSize: cellSize,
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
}
