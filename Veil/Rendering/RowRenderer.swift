import AppKit
import CoreText

nonisolated private let defaultAttrs = CellAttributes()

nonisolated final class RowRenderer: @unchecked Sendable {
    private var cellSize: CGSize
    private let glyphCache: GlyphCache

    init(cellSize: CGSize, glyphCache: GlyphCache) {
        self.cellSize = cellSize
        self.glyphCache = glyphCache
    }

    func updateCellSize(_ newSize: CGSize) {
        self.cellSize = newSize
    }

    /// Render a single grid row to a CGImage.
    func render(
        row: [Cell],
        attributes: [Int: CellAttributes],
        defaultFg: Int,
        defaultBg: Int,
        scale: CGFloat = 2.0
    ) -> CGImage? {
        let cols = row.count
        guard cols > 0 else { return nil }

        let pointWidth = cellSize.width * CGFloat(cols)
        let pointHeight = cellSize.height
        let pixelWidth = Int(ceil(pointWidth * scale))
        let pixelHeight = Int(ceil(pointHeight * scale))
        guard pixelWidth > 0 && pixelHeight > 0 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let ctx = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        ctx.scaleBy(x: scale, y: scale)

        // Fill entire row with default background
        let defaultBgColor = NSColor(rgb: defaultBg)
        ctx.setFillColor(defaultBgColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight))

        // Pass 1: backgrounds (per-cell, no ligature interaction)
        var col = 0
        while col < cols {
            let cell = row[col]
            let text = cell.text
            let attrs = attributes[cell.hlId] ?? defaultAttrs

            let isDoubleWidth =
                !text.isEmpty && text != " " && col + 1 < cols && row[col + 1].text.isEmpty
            let cellCount = isDoubleWidth ? 2 : 1

            let bg = attrs.effectiveBackground(defaultFg: defaultFg, defaultBg: defaultBg)
            if bg != defaultBg {
                let drawWidth = cellSize.width * CGFloat(cellCount)
                let x = CGFloat(col) * cellSize.width
                ctx.setFillColor(NSColor(rgb: bg).cgColor)
                ctx.fill(CGRect(x: x, y: 0, width: drawWidth, height: cellSize.height))
            }

            if text.isEmpty || text == " " {
                col += 1
            } else {
                col += cellCount
            }
        }

        // Pass 2: foreground glyphs with ligature support
        let font = glyphCache.font
        col = 0
        while col < cols {
            let cell = row[col]
            let text = cell.text

            if text.isEmpty || text == " " {
                col += 1
                continue
            }

            let attrs = attributes[cell.hlId] ?? defaultAttrs
            let isDoubleWidth = col + 1 < cols && row[col + 1].text.isEmpty

            if isDoubleWidth {
                let x = CGFloat(col) * cellSize.width
                let glyph = glyphCache.get(
                    text: text, attrs: attrs, defaultFg: defaultFg, defaultBg: defaultBg,
                    cellCount: 2)
                // Multi-cell glyphs render at their natural advance; the grid
                // cursor still steps by 2 cells so alignment is preserved.
                let cellRect = CGRect(
                    x: x, y: 0, width: glyph.drawWidth, height: cellSize.height)
                ctx.draw(glyph.image, in: cellRect)
                col += 2
                continue
            }

            // Collect run of same-hlId single-width non-space non-empty cells
            let runStartCol = col
            let runHlId = cell.hlId
            var runEnd = col + 1
            while runEnd < cols {
                let c = row[runEnd]
                if c.text.isEmpty || c.text == " " || c.hlId != runHlId { break }
                if runEnd + 1 < cols && row[runEnd + 1].text.isEmpty { break }
                runEnd += 1
            }

            let runLen = runEnd - runStartCol
            let shaped: [ShapedGlyph]
            if runLen == 1 {
                shaped = [ShapedGlyph(text: text, colOffset: 0, cellCount: 1)]
            } else {
                var runText = ""
                for i in runStartCol..<runEnd { runText += row[i].text }
                shaped = shapeRunText(
                    runText, font: font, bold: attrs.bold, italic: attrs.italic)
            }

            for glyph in shaped {
                let glyphCol = runStartCol + glyph.colOffset
                let x = CGFloat(glyphCol) * cellSize.width
                let cached = glyphCache.get(
                    text: glyph.text, attrs: attrs, defaultFg: defaultFg,
                    defaultBg: defaultBg, cellCount: glyph.cellCount)
                // Multi-cell glyphs use their natural advance; single-cell
                // glyphs fill the allocated cell width as before.
                let drawWidth =
                    glyph.cellCount >= 2
                    ? cached.drawWidth
                    : cellSize.width * CGFloat(glyph.cellCount)
                let cellRect = CGRect(
                    x: x, y: 0, width: drawWidth, height: cellSize.height)
                ctx.draw(cached.image, in: cellRect)
            }

            col = runEnd
        }

        return ctx.makeImage()
    }
}
