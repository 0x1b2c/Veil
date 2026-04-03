import Metal
import AppKit
import CoreText

nonisolated final class GlyphAtlas {
    struct Region {
        let u: Float  // left UV (0-1)
        let v: Float  // top UV (0-1)
        let uMax: Float  // right UV
        let vMax: Float  // bottom UV
        let drawWidth: Float  // actual rendered width in points (multiply by scale for pixels)
    }

    // Color-independent cache key: glyphs are rendered as white alpha masks
    // so the same glyph can be reused regardless of foreground or background color.
    // Colors are applied per-vertex in the fragment shader.
    struct Key: Hashable {
        let text: String
        let fontName: String
        let fontSize: CGFloat
        let bold: Bool
        let italic: Bool
        let cellCount: Int
    }

    var regionCount: Int { regions.count }

    private let device: MTLDevice
    private(set) var texture: MTLTexture!
    private var regions: [Key: Region] = [:]
    private var nextX: Int = 0
    private var nextY: Int = 0
    private var currentRowHeight: Int = 0
    private let atlasWidth: Int
    private(set) var atlasHeight: Int
    private let maxAtlasHeight = 8192
    var scale: CGFloat = 2.0

    init(device: MTLDevice, size: Int = 2048) {
        self.device = device
        self.atlasWidth = size
        self.atlasHeight = size
        self.texture = createTexture(width: size, height: size)
        self.nextX = 1  // Reserve pixel (0,0) as transparent sentinel for empty cells
        FontFallback.probe()
    }

    func region(
        text: String, font: NSFont, bold: Bool, italic: Bool,
        cellSize: CGSize, cellCount: Int = 1
    ) -> Region {
        let key = Key(
            text: text, fontName: font.fontName, fontSize: font.pointSize,
            bold: bold, italic: italic,
            cellCount: cellCount)

        if let existing = regions[key] { return existing }

        // Resolve font variant for measuring
        var drawFont = font
        if bold {
            let descriptor = drawFont.fontDescriptor.withSymbolicTraits(.bold)
            drawFont = NSFont(descriptor: descriptor, size: drawFont.pointSize) ?? drawFont
        }
        if italic {
            let descriptor = drawFont.fontDescriptor.withSymbolicTraits(.italic)
            drawFont = NSFont(descriptor: descriptor, size: drawFont.pointSize) ?? drawFont
        }

        drawFont = FontFallback.resolveFont(drawFont, for: text)

        // Measure actual glyph ink width. Nerd font icons often have bounding
        // boxes wider than the cell width neovim allocates. Rendering at the
        // natural width allows the overflow logic in MetalRenderer to display
        // them fully when followed by a space (WezTerm-style approach).
        let allocatedWidth = cellSize.width * CGFloat(cellCount)
        let attributes: [NSAttributedString.Key: Any] = [.font: drawFont]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let naturalWidth = glyphBounds.origin.x + glyphBounds.size.width

        // Use the larger of allocated and natural width for rendering
        let renderWidth = max(allocatedWidth, naturalWidth)
        let pixelW = Int(ceil(renderWidth * scale))
        let pixelH = Int(ceil(cellSize.height * scale))

        // Check if we need to move to next row
        if nextX + pixelW > atlasWidth {
            nextX = 0
            nextY += currentRowHeight
            currentRowHeight = 0
        }

        // Grow atlas vertically if out of space, fall back to full
        // invalidation only at the maximum supported texture size.
        if nextY + pixelH > atlasHeight {
            if atlasHeight < maxAtlasHeight {
                growAtlas()
            } else {
                invalidate()
            }
        }

        // Render glyph as white alpha mask (color applied in fragment shader)
        let imageData = renderGlyph(
            text: text, font: drawFont,
            width: pixelW, height: pixelH,
            drawWidth: renderWidth, cellHeight: cellSize.height)

        // Copy to atlas texture
        let mtlRegion = MTLRegionMake2D(nextX, nextY, pixelW, pixelH)
        texture.replace(
            region: mtlRegion, mipmapLevel: 0,
            withBytes: imageData, bytesPerRow: pixelW * 4)

        // Calculate UV coordinates
        let uvRegion = Region(
            u: Float(nextX) / Float(atlasWidth),
            v: Float(nextY) / Float(atlasHeight),
            uMax: Float(nextX + pixelW) / Float(atlasWidth),
            vMax: Float(nextY + pixelH) / Float(atlasHeight),
            drawWidth: Float(renderWidth)
        )

        regions[key] = uvRegion
        nextX += pixelW
        currentRowHeight = max(currentRowHeight, pixelH)

        return uvRegion
    }

    func invalidate() {
        regions.removeAll()
        nextX = 1  // Reserve pixel (0,0) as transparent sentinel
        nextY = 0
        currentRowHeight = 0
        // Clear texture
        texture = createTexture(width: atlasWidth, height: atlasHeight)
    }

    // MARK: - Private

    /// Double the atlas height and blit existing content to the new texture.
    /// Rescales all cached UV v-coordinates to account for the new height.
    /// This avoids a full invalidation which would discard all cached glyphs.
    private func growAtlas() {
        let newHeight = min(atlasHeight * 2, maxAtlasHeight)
        let newTexture = createTexture(width: atlasWidth, height: newHeight)

        // Blit existing atlas content to the new texture
        guard let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            invalidate()
            return
        }
        blit.copy(
            from: texture, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: atlasWidth, height: atlasHeight, depth: 1),
            to: newTexture, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Rescale UV v-coordinates for the new height
        let vScale = Float(atlasHeight) / Float(newHeight)
        var rescaled: [Key: Region] = [:]
        for (key, region) in regions {
            rescaled[key] = Region(
                u: region.u, v: region.v * vScale,
                uMax: region.uMax, vMax: region.vMax * vScale,
                drawWidth: region.drawWidth)
        }
        regions = rescaled

        texture = newTexture
        atlasHeight = newHeight
    }

    private func createTexture(width: Int, height: Int) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed  // CPU-writable, GPU-readable on macOS
        let texture = device.makeTexture(descriptor: descriptor)!
        // Clear the sentinel pixel at (0,0) to guarantee transparency.
        // Background and cursor quads sample this pixel; Metal does not
        // guarantee initial texture contents.
        let zero: [UInt8] = [0, 0, 0, 0]
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0, withBytes: zero, bytesPerRow: 4
        )
        return texture
    }

    /// Render glyph as a white alpha mask on transparent background.
    /// The fragment shader multiplies this mask by the per-vertex fgColor,
    /// allowing the same atlas entry to be reused across all color combinations.
    private func renderGlyph(
        text: String, font: NSFont,
        width: Int, height: Int,
        drawWidth: CGFloat, cellHeight: CGFloat
    ) -> [UInt8] {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        // premultipliedFirst + byteOrder32Little = BGRA byte order, matching .bgra8Unorm
        guard
            let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { return Array(repeating: 0, count: width * height * 4) }

        ctx.scaleBy(x: scale, y: scale)

        // Background is left transparent (zeroed memory from CGContext init).
        // Glyph is rendered in white; the shader colorizes via per-vertex fgColor.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)

        // Position baseline (centered in the potentially taller cell)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let naturalHeight = CTFontGetAscent(font) + descent + leading
        let extraPadding = (cellHeight - naturalHeight) / 2
        let baselineY = descent + leading + extraPadding

        ctx.textPosition = CGPoint(x: 0, y: baselineY)
        CTLineDraw(line, ctx)

        // Extract pixel data
        guard let data = ctx.data else { return Array(repeating: 0, count: width * height * 4) }
        return Array(
            UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: UInt8.self),
                count: width * height * 4))
    }
}
