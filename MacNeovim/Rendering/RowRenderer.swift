import AppKit
import CoreText

private let defaultAttrs = CellAttributes()

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
        defaultBg: Int
    ) -> CGImage? {
        let cols = row.count
        guard cols > 0 else { return nil }

        let width = Int(ceil(cellSize.width * CGFloat(cols)))
        let height = Int(ceil(cellSize.height))
        guard width > 0 && height > 0 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Fill entire row with default background
        let defaultBgColor = NSColor(rgb: defaultBg)
        ctx.setFillColor(defaultBgColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for col in 0..<cols {
            let cell = row[col]
            let x = CGFloat(col) * cellSize.width
            let cellRect = CGRect(x: x, y: 0, width: cellSize.width, height: cellSize.height)
            let attrs = attributes[cell.hlId] ?? defaultAttrs

            let bg = attrs.effectiveBackground(defaultFg: defaultFg, defaultBg: defaultBg)

            // Fill cell background if different from default
            if bg != defaultBg {
                let bgColor = NSColor(rgb: bg)
                ctx.setFillColor(bgColor.cgColor)
                ctx.fill(cellRect)
            }

            // Skip rendering for spaces and empty text
            let text = cell.text
            if text == " " || text.isEmpty { continue }

            // Get glyph image from cache and composite
            let glyphImage = glyphCache.get(text: text, attrs: attrs, defaultFg: defaultFg, defaultBg: defaultBg)
            ctx.draw(glyphImage, in: cellRect)
        }

        return ctx.makeImage()
    }
}
