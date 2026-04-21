import Metal
import AppKit
import CoreText

nonisolated(unsafe) var ligaturesEnabled = true

struct ShapedGlyph {
    let text: String
    let colOffset: Int
    let cellCount: Int
}

/// Shape a run of text using CoreText to detect font ligatures.
/// Handles both traditional ligatures (glyph merging, fewer glyphs) and
/// contextual alternates (calt, same glyph count but different glyph IDs).
/// Most programming fonts (Fira Code, JetBrains Mono) use calt.
nonisolated func shapeRunText(
    _ runText: String, font: NSFont, bold: Bool, italic: Bool
) -> [ShapedGlyph] {
    if !ligaturesEnabled { return perCharacterGlyphs(runText) }

    var drawFont = font
    var traits: NSFontDescriptor.SymbolicTraits = []
    if bold { traits.insert(.bold) }
    if italic { traits.insert(.italic) }
    if !traits.isEmpty {
        let descriptor = drawFont.fontDescriptor.withSymbolicTraits(traits)
        drawFont = NSFont(descriptor: descriptor, size: drawFont.pointSize) ?? drawFont
    }

    let attributes: [NSAttributedString.Key: Any] = [.font: drawFont]
    let attrString = NSAttributedString(string: runText, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attrString)
    let ctRuns = CTLineGetGlyphRuns(line) as! [CTRun]

    // Extract shaped glyph IDs from CTLine (with OpenType features applied)
    var shapedIDs = [CGGlyph]()
    for ctRun in ctRuns {
        let count = CTRunGetGlyphCount(ctRun)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        CTRunGetGlyphs(ctRun, CFRange(location: 0, length: count), &glyphs)
        shapedIDs.append(contentsOf: glyphs)
    }

    let utf16 = Array(runText.utf16)

    // When shaped glyph count matches UTF-16 count, check for contextual alternates
    // by comparing shaped glyph IDs against unshaped (cmap-only) glyph IDs
    if shapedIDs.count == utf16.count {
        var unshapedIDs = [CGGlyph](repeating: 0, count: utf16.count)
        let allCovered = CTFontGetGlyphsForCharacters(
            drawFont, utf16, &unshapedIDs, utf16.count)

        if !allCovered || shapedIDs == unshapedIDs {
            return perCharacterGlyphs(runText)
        }

        // Contextual alternates detected: group consecutive changed glyphs
        var utf16ToCol = [Int]()
        var colIdx = 0
        for char in runText {
            for _ in 0..<char.utf16.count { utf16ToCol.append(colIdx) }
            colIdx += 1
        }

        var result = [ShapedGlyph]()
        var i = 0
        while i < utf16.count {
            let col = utf16ToCol[i]
            if shapedIDs[i] == unshapedIDs[i] {
                var end = i + 1
                while end < utf16.count && utf16ToCol[end] == col { end += 1 }
                let startIdx = runText.utf16.index(
                    runText.utf16.startIndex, offsetBy: i)
                let endIdx = runText.utf16.index(
                    runText.utf16.startIndex, offsetBy: end)
                result.append(
                    ShapedGlyph(
                        text: String(runText[startIdx..<endIdx]),
                        colOffset: col, cellCount: 1))
                i = end
            } else {
                var end = i
                while end < utf16.count && shapedIDs[end] != unshapedIDs[end] {
                    end += 1
                }
                let endCol = (end < utf16ToCol.count) ? utf16ToCol[end] : colIdx
                let cellCount = max(endCol - col, 1)
                let startIdx = runText.utf16.index(
                    runText.utf16.startIndex, offsetBy: i)
                let endIdx = runText.utf16.index(
                    runText.utf16.startIndex, offsetBy: end)
                result.append(
                    ShapedGlyph(
                        text: String(runText[startIdx..<endIdx]),
                        colOffset: col, cellCount: cellCount))
                i = end
            }
        }
        return result
    }

    // Traditional ligature: fewer glyphs than characters (glyph merging)
    var utf16ToCol = [Int]()
    var colIdx = 0
    for char in runText {
        for _ in 0..<char.utf16.count { utf16ToCol.append(colIdx) }
        colIdx += 1
    }
    let totalCols = colIdx

    var result = [ShapedGlyph]()
    for ctRun in ctRuns {
        let glyphCount = CTRunGetGlyphCount(ctRun)
        guard glyphCount > 0 else { continue }

        var indices = [CFIndex](repeating: 0, count: glyphCount)
        CTRunGetStringIndices(ctRun, CFRange(location: 0, length: glyphCount), &indices)
        let runRange = CTRunGetStringRange(ctRun)
        let runStringEnd = runRange.location + runRange.length

        for i in 0..<glyphCount {
            let utf16Start = indices[i]
            let utf16End = (i + 1 < glyphCount) ? indices[i + 1] : runStringEnd

            let startCol = utf16ToCol[utf16Start]
            let endCol = (utf16End < utf16ToCol.count) ? utf16ToCol[utf16End] : totalCols
            let cellCount = max(endCol - startCol, 1)

            let startIdx = runText.utf16.index(
                runText.utf16.startIndex, offsetBy: utf16Start)
            let endIdx = runText.utf16.index(
                runText.utf16.startIndex, offsetBy: utf16End)
            result.append(
                ShapedGlyph(
                    text: String(runText[startIdx..<endIdx]),
                    colOffset: startCol, cellCount: cellCount))
        }
    }

    return result.isEmpty ? perCharacterGlyphs(runText) : result
}

nonisolated private func perCharacterGlyphs(_ text: String) -> [ShapedGlyph] {
    var result = [ShapedGlyph]()
    result.reserveCapacity(text.count)
    var col = 0
    for char in text {
        result.append(ShapedGlyph(text: String(char), colOffset: col, cellCount: 1))
        col += 1
    }
    return result
}

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

    private struct ShapingKey: Hashable {
        let text: String
        let fontName: String
        let fontSize: CGFloat
        let bold: Bool
        let italic: Bool
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
    private var shapingCache: [ShapingKey: [ShapedGlyph]] = [:]

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

        // Measure glyph width. For single-cell glyphs we use ink bounds and
        // take max(allocated, ink) so overflowing shapes (Nerd Font icons,
        // italic Latin descenders) can spill past the cell when followed by
        // a space. For multi-cell glyphs (CJK, wide ligatures) we use the
        // typographic advance instead, so the glyph renders at its natural
        // width rather than being stretched or compressed into the cell grid.
        let allocatedWidth = cellSize.width * CGFloat(cellCount)
        let attributes: [NSAttributedString.Key: Any] = [.font: drawFont]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)

        // Custom-drawn box-drawing/block characters use exact cell
        // dimensions; skip natural width to avoid bitmap/quad mismatch.
        let isCustomDrawn =
            text.unicodeScalars.count == 1
            && (0x2500...0x259F).contains(text.unicodeScalars.first!.value)

        let renderWidth: CGFloat
        if isCustomDrawn {
            renderWidth = allocatedWidth
        } else if cellCount >= 2 {
            // Typographic bounds give the sum of advances — the correct
            // layout width for CJK and other wide glyphs.
            let advanceBounds = CTLineGetBoundsWithOptions(line, [])
            renderWidth = advanceBounds.origin.x + advanceBounds.size.width
        } else {
            let inkBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let naturalWidth = inkBounds.origin.x + inkBounds.size.width
            renderWidth = max(allocatedWidth, naturalWidth)
        }
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

        // Render glyph as a single-channel coverage mask. The fragment shader
        // multiplies this coverage against the per-vertex foreground color.
        let imageData = renderGlyph(
            text: text, font: drawFont,
            width: pixelW, height: pixelH,
            drawWidth: renderWidth, cellHeight: cellSize.height)

        // Copy to atlas texture (1 byte per pixel, matches .r8Unorm)
        let mtlRegion = MTLRegionMake2D(nextX, nextY, pixelW, pixelH)
        texture.replace(
            region: mtlRegion, mipmapLevel: 0,
            withBytes: imageData, bytesPerRow: pixelW)

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

    func shapeRun(
        _ runText: String, font: NSFont, bold: Bool, italic: Bool
    ) -> [ShapedGlyph] {
        let key = ShapingKey(
            text: runText, fontName: font.fontName, fontSize: font.pointSize,
            bold: bold, italic: italic)
        if let cached = shapingCache[key] { return cached }
        let result = shapeRunText(runText, font: font, bold: bold, italic: italic)
        shapingCache[key] = result
        return result
    }

    func invalidate() {
        regions.removeAll()
        shapingCache.removeAll()
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
        // Single-channel coverage atlas: 1 byte per pixel, 4x less memory
        // than BGRA. The fragment shader samples `.r` to get the glyph's
        // coverage mask and applies the foreground color itself.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed  // CPU-writable, GPU-readable on macOS
        let texture = device.makeTexture(descriptor: descriptor)!
        // Clear the sentinel pixel at (0,0) to guarantee zero coverage.
        // Background and cursor quads sample this pixel; Metal does not
        // guarantee initial texture contents.
        let zero: [UInt8] = [0]
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0, withBytes: zero, bytesPerRow: 1
        )
        return texture
    }

    /// Render glyph as a single-channel coverage mask in a linearGray +
    /// alpha-only CGBitmapContext. CoreText's text rendering produces
    /// coverage values directly (as opposed to sRGB-premultiplied color),
    /// matching Ghostty's grayscale rasterization path. The fragment shader
    /// multiplies this coverage by the per-vertex fgColor, so the same atlas
    /// entry serves every color combination.
    private func renderGlyph(
        text: String, font: NSFont,
        width: Int, height: Int,
        drawWidth: CGFloat, cellHeight: CGFloat
    ) -> [UInt8] {
        let colorSpace = CGColorSpace(name: CGColorSpace.linearGray)!
        guard
            let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            )
        else { return Array(repeating: 0, count: width * height) }

        // Font smoothing flags — matches Ghostty's coretext path.
        // `shouldSmoothFonts` (thickening) is intentionally off; it is a
        // style choice rather than a correctness fix, and can be exposed
        // through a config option later.
        ctx.setAllowsFontSmoothing(true)
        ctx.setShouldSmoothFonts(false)
        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.setAllowsFontSubpixelQuantization(false)
        ctx.setShouldSubpixelQuantizeFonts(false)

        ctx.scaleBy(x: scale, y: scale)

        // Background is zeroed (no coverage). Glyph is rendered in white;
        // the shader colorizes via per-vertex fgColor.
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

        let scalar = text.unicodeScalars.first
        if let scalar, text.unicodeScalars.count == 1,
            BoxDrawing.render(
                scalar.value, ctx: ctx,
                cellWidth: drawWidth, cellHeight: cellHeight, font: font)
        {
            // Custom drawing handled
        } else {
            ctx.textPosition = CGPoint(x: 0, y: baselineY)
            CTLineDraw(line, ctx)
        }

        // Extract pixel data (1 byte per pixel)
        guard let data = ctx.data else { return Array(repeating: 0, count: width * height) }
        return Array(
            UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: UInt8.self),
                count: width * height))
    }
}
