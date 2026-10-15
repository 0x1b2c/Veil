import Metal
import MetalKit
import AppKit
import QuartzCore

nonisolated final class MetalRenderer {
    struct Vertex {
        var position: SIMD2<Float>  // pixel position
        var texCoord: SIMD2<Float>  // UV in atlas
        var fgColor: SIMD4<Float>  // foreground color (applied to glyph alpha mask)
        var bgColor: SIMD4<Float>  // background color
    }

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState

    // Pre-allocated vertex buffers to avoid per-frame MTLBuffer creation,
    // rewritten via contents() pointer instead of makeBuffer(). One per frame
    // the GPU may still be reading, used in rotation: the CPU waits for a free
    // slot before writing, so it never overwrites vertices of a frame in flight.
    static let maxFramesInFlight = 3
    private let freeFrameSlots = DispatchSemaphore(value: maxFramesInFlight)
    private var vertexBuffers: [MTLBuffer?] = Array(repeating: nil, count: maxFramesInFlight)
    private var frameSlot = 0
    private(set) var lastVertexBuffer: MTLBuffer?

    // Persistent per-row vertex data for dirty-region rendering.
    // Only rows marked dirty are rebuilt; unchanged rows reuse cached vertices.
    // Each row's background and foreground vertices are stored separately.
    private var rowBackgroundVertices: [[Vertex]] = []
    private(set) var rowForegroundVertices: [[Vertex]] = []
    private var cachedRows: Int = 0
    private var cachedCols: Int = 0
    private(set) var lastVertexCount: Int = 0

    // Rows whose cached vertices are out of date. The caller hands over its
    // dirty rows every frame and may forget them afterwards, so rows that a
    // frame could not rebuild stay here until a later frame does.
    private var pendingRows = IndexSet()

    // Everything baked into the cached vertices besides the cells themselves:
    // atlas texture coordinates and pixel geometry. When any of it changes,
    // every cached row is stale, dirty or not.
    private struct RowCacheBasis: Equatable {
        var atlasGeneration: Int
        var scale: Float
        var cellSize: CGSize
        var gridTopPadding: CGFloat
    }
    private var rowCacheBasis: RowCacheBasis?

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalRendererError.noDevice
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw MetalRendererError.noCommandQueue
        }
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary() else {
            throw MetalRendererError.noLibrary
        }
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        // Premultiplied-alpha blending: the fragment shader outputs genuinely
        // premultiplied color, and the hardware combines with the destination
        // using over-compositing (src + dst*(1-src.a)).
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // Set up vertex descriptor for the vertex buffer layout
        let vertexDescriptor = MTLVertexDescriptor()
        // position: float2
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // texCoord: float2
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        // fgColor: float4 (foreground color for glyph colorization in shader)
        vertexDescriptor.attributes[2].format = .float4
        vertexDescriptor.attributes[2].offset = MemoryLayout<Float>.size * 4
        vertexDescriptor.attributes[2].bufferIndex = 0
        // bgColor: float4
        vertexDescriptor.attributes[3].format = .float4
        vertexDescriptor.attributes[3].offset = MemoryLayout<Float>.size * 8
        vertexDescriptor.attributes[3].bufferIndex = 0
        // stride: 2 + 2 + 4 + 4 = 12 floats
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 12
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        descriptor.vertexDescriptor = vertexDescriptor

        self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Rendering

    /// Returns false when nothing was presented (no drawable or command
    /// buffer was available), so the caller can schedule another frame.
    @discardableResult
    func render(
        cells: [[Cell]], attributes: [Int: CellAttributes],
        rows: Int, cols: Int,
        dirtyRows: IndexSet,
        atlas: GlyphAtlas, font: NSFont, cellSize: CGSize,
        gridTopPadding: CGFloat, defaultFg: Int, defaultBg: Int,
        cursorPosition: Position, cursorShape: ModeInfo.CursorShape,
        cursorCellPercentage: Int,
        debugOverlay: String?,
        in metalLayer: CAMetalLayer
    ) -> Bool {
        pendingRows.formUnion(dirtyRows)
        // Nothing to draw yet; the first grid_resize marks every row dirty.
        guard rows > 0, cols > 0, cells.count >= rows else { return true }

        let scale = Float(metalLayer.contentsScale)
        let cellW = Float(cellSize.width) * scale
        let cellH = Float(cellSize.height) * scale
        let topPad = Float(gridTopPadding) * scale

        // Resize per-row caches when grid dimensions change
        resizeRowCaches(rows: rows, cols: cols)

        let basis = RowCacheBasis(
            atlasGeneration: atlas.generation, scale: scale,
            cellSize: cellSize, gridTopPadding: gridTopPadding)
        if basis != rowCacheBasis {
            pendingRows = IndexSet(0..<rows)
        }

        // Rebuild vertex data only for rows that Grid marked as dirty.
        // Cursor is drawn as an independent quad, so cursor movement alone
        // does not require rebuilding row vertices. A new glyph can grow or
        // clear the atlas midway, invalidating rows already rebuilt in this
        // pass; rebuild everything again then. The second pass finds every
        // glyph cached, so it settles; the bound only guards a screen whose
        // glyphs cannot all fit in the largest atlas.
        var passes = 0
        repeat {
            let generation = atlas.generation
            for row in pendingRows {
                guard row < rows, cells[row].count >= cols else { continue }
                rebuildRowVertices(
                    row: row, cells: cells[row], attributes: attributes,
                    cols: cols, atlas: atlas, font: font, cellSize: cellSize,
                    cellW: cellW, cellH: cellH, topPad: topPad, scale: scale,
                    defaultFg: defaultFg, defaultBg: defaultBg)
            }
            passes += 1
            if atlas.generation == generation { break }
            pendingRows = IndexSet(0..<rows)
        } while passes < 3
        pendingRows.removeAll()
        rowCacheBasis = RowCacheBasis(
            atlasGeneration: atlas.generation, scale: scale,
            cellSize: cellSize, gridTopPadding: gridTopPadding)

        // Count total vertices across all row caches + cursor quad,
        // then write directly into the Metal buffer to avoid assembling
        // an intermediate Swift array and copying it a second time.
        let cursorVertexCount = 6
        var totalVertices = cursorVertexCount
        for row in 0..<rows {
            totalVertices += rowBackgroundVertices[row].count
            totalVertices += rowForegroundVertices[row].count
        }
        guard totalVertices > 0 else { return false }

        // Every return below this point either hands the slot to the command
        // buffer, which frees it on completion, or frees it here.
        freeFrameSlots.wait()
        var slotHandedToGPU = false
        defer {
            if !slotHandedToGPU { freeFrameSlots.signal() }
        }

        guard let vertexBuffer = ensureVertexBuffer(vertexCount: totalVertices, slot: frameSlot)
        else {
            return false
        }
        lastVertexBuffer = vertexBuffer
        let dst = vertexBuffer.contents().assumingMemoryBound(to: Vertex.self)
        var offset = 0

        // All backgrounds first, then all foreground glyphs, so glyph
        // quads always draw on top of background quads.
        for row in 0..<rows {
            let bg = rowBackgroundVertices[row]
            if !bg.isEmpty {
                bg.withUnsafeBufferPointer { buf in
                    dst.advanced(by: offset).update(from: buf.baseAddress!, count: buf.count)
                }
                offset += bg.count
            }
        }
        for row in 0..<rows {
            let fg = rowForegroundVertices[row]
            if !fg.isEmpty {
                fg.withUnsafeBufferPointer { buf in
                    dst.advanced(by: offset).update(from: buf.baseAddress!, count: buf.count)
                }
                offset += fg.count
            }
        }

        // Cursor quad (always on top of everything)
        let emptyRegion = GlyphAtlas.Region(u: 0, v: 0, uMax: 0, vMax: 0, drawWidth: 0)
        let cx = Float(cursorPosition.col) * cellW
        var cy = topPad + Float(cursorPosition.row) * cellH
        let cursorRow = cursorPosition.row
        let cursorCol = cursorPosition.col
        let isDoubleWidth =
            cursorRow < rows && cursorCol + 1 < cols
            && cells[cursorRow][cursorCol + 1].text.isEmpty
        let cursorCellW = isDoubleWidth ? cellW * 2 : cellW
        var cw = cursorCellW
        var ch = cellH
        let pct = Float(max(10, cursorCellPercentage)) / 100.0
        switch cursorShape {
        case .block:
            break
        case .vertical:
            cw = max(2 * scale, cursorCellW * pct)
        case .horizontal:
            ch = max(2 * scale, cellH * pct)
            cy += cellH - ch  // Anchor horizontal bar at bottom of cell
        }
        var cursorColor = colorToSIMD4(defaultFg)
        cursorColor.w = 0.5
        var cursorVerts: [Vertex] = []
        addQuad(
            to: &cursorVerts, x: cx, y: cy, w: cw, h: ch,
            region: emptyRegion, bgColor: cursorColor)
        cursorVerts.withUnsafeBufferPointer { buf in
            dst.advanced(by: offset).update(from: buf.baseAddress!, count: buf.count)
        }
        offset += cursorVerts.count
        lastVertexCount = offset

        var uniforms = SIMD2<Float>(
            Float(metalLayer.drawableSize.width),
            Float(metalLayer.drawableSize.height))

        // Acquired after the CPU work, as late as possible: nextDrawable()
        // blocks while every drawable is in use.
        guard let drawable = metalLayer.nextDrawable() else { return false }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double((defaultBg >> 16) & 0xFF) / 255.0,
            green: Double((defaultBg >> 8) & 0xFF) / 255.0,
            blue: Double(defaultBg & 0xFF) / 255.0,
            alpha: 1.0
        )
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return false }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        encoder.setFragmentTexture(atlas.texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: offset)

        if let debugOverlay {
            renderDebugOverlay(
                text: debugOverlay, scale: scale,
                encoder: encoder,
                viewportWidth: Float(metalLayer.drawableSize.width),
                viewportHeight: Float(metalLayer.drawableSize.height))
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [freeFrameSlots] _ in freeFrameSlots.signal() }
        slotHandedToGPU = true
        commandBuffer.commit()
        frameSlot = (frameSlot + 1) % Self.maxFramesInFlight
        return true
    }

    private func addQuad(
        to vertices: inout [Vertex],
        x: Float, y: Float, w: Float, h: Float,
        region: GlyphAtlas.Region,
        fgColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0),
        bgColor: SIMD4<Float>
    ) {
        // Two triangles forming a quad
        let v0 = Vertex(
            position: SIMD2(x, y), texCoord: SIMD2(region.u, region.v), fgColor: fgColor,
            bgColor: bgColor)
        let v1 = Vertex(
            position: SIMD2(x + w, y), texCoord: SIMD2(region.uMax, region.v), fgColor: fgColor,
            bgColor: bgColor)
        let v2 = Vertex(
            position: SIMD2(x, y + h), texCoord: SIMD2(region.u, region.vMax), fgColor: fgColor,
            bgColor: bgColor)
        let v3 = Vertex(
            position: SIMD2(x + w, y + h), texCoord: SIMD2(region.uMax, region.vMax),
            fgColor: fgColor, bgColor: bgColor)
        vertices.append(v0)
        vertices.append(v1)
        vertices.append(v2)
        vertices.append(v1)
        vertices.append(v3)
        vertices.append(v2)
    }

    // MARK: - Debug Overlay

    private func renderDebugOverlay(
        text: String, scale: Float,
        encoder: MTLRenderCommandEncoder,
        viewportWidth: Float, viewportHeight: Float
    ) {
        // Render debug text into a CGImage using CoreText
        let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)

        // Measure text size using CTFramesetter (thread-safe, no AppKit dependency)
        let cfAttrString = attrString as CFAttributedString
        let framesetter = CTFramesetterCreateWithAttributedString(cfAttrString)
        let textRect = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0),
            nil, CGSize(width: 2048, height: 1024), nil
        )

        let padding: CGFloat = 8
        let width = ceil(textRect.width + padding * 2)
        let height = ceil(textRect.height + padding * 2)
        let pixelW = Int(width * CGFloat(scale))
        let pixelH = Int(height * CGFloat(scale))
        guard pixelW > 0, pixelH > 0 else { return }

        // Render to CGContext
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let ctx = CGContext(
                data: nil, width: pixelW, height: pixelH,
                bitsPerComponent: 8, bytesPerRow: pixelW * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }

        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

        // Semi-transparent dark background with rounded corners
        let bgRect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(NSColor(white: 0, alpha: 0.7).cgColor)
        let path = CGPath(roundedRect: bgRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        // Draw text (flip coordinates for NSAttributedString drawing)
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        ctx.saveGState()
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
        let drawRect = CGRect(
            x: padding, y: padding, width: textRect.width, height: textRect.height)
        attrString.draw(in: drawRect)
        ctx.restoreGState()
        NSGraphicsContext.restoreGraphicsState()

        guard let image = ctx.makeImage() else { return }

        // Create temporary texture from rendered image
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: pixelW, height: pixelH,
            mipmapped: false)
        texDesc.usage = .shaderRead
        texDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: texDesc),
            let data = image.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data)
        else { return }
        texture.replace(
            region: MTLRegionMake2D(0, 0, pixelW, pixelH),
            mipmapLevel: 0, withBytes: bytes, bytesPerRow: pixelW * 4)

        // Position at top-left with margin
        let margin: Float = 10 * scale
        let quadW = Float(width) * scale
        let quadH = Float(height) * scale
        let x = margin
        let y = margin

        // Draw overlay quad using the overlay texture
        var overlayVertices: [Vertex] = []
        let region = GlyphAtlas.Region(u: 0, v: 0, uMax: 1, vMax: 1, drawWidth: Float(width))
        addQuad(
            to: &overlayVertices, x: x, y: y, w: quadW, h: quadH,
            region: region, bgColor: SIMD4<Float>(0, 0, 0, 0))

        let bufferSize = overlayVertices.count * MemoryLayout<Vertex>.stride
        guard
            let vertexBuffer = device.makeBuffer(
                bytes: overlayVertices, length: bufferSize,
                options: .storageModeShared)
        else { return }

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: overlayVertices.count)
    }

    // MARK: - Dirty-region helpers

    /// Reset per-row vertex caches when the grid dimensions change.
    private func resizeRowCaches(rows: Int, cols: Int) {
        guard rows != cachedRows || cols != cachedCols else { return }
        rowBackgroundVertices = Array(repeating: [], count: rows)
        rowForegroundVertices = Array(repeating: [], count: rows)
        cachedRows = rows
        cachedCols = cols
        // Emptied caches must all be rebuilt, whatever the caller marked dirty.
        pendingRows = IndexSet(0..<rows)
    }

    /// Rebuild background and foreground vertices for a single row.
    /// Called only for dirty rows, avoiding redundant work on unchanged content.
    ///
    /// Two-pass rendering (WezTerm-style): backgrounds first, then foreground
    /// glyphs on top. This allows glyphs to overflow into adjacent cells
    /// without being covered by the neighbor's background quad. Nerd font
    /// icons whose bounding box exceeds the cell width are handled as:
    ///   - Followed by space: render at natural width (overflow into space)
    ///   - Followed by content: scale down to fit cell (better than clipping)
    private func rebuildRowVertices(
        row: Int, cells: [Cell], attributes: [Int: CellAttributes],
        cols: Int, atlas: GlyphAtlas, font: NSFont, cellSize: CGSize,
        cellW: Float, cellH: Float, topPad: Float, scale: Float,
        defaultFg: Int, defaultBg: Int
    ) {
        let emptyRegion = GlyphAtlas.Region(u: 0, v: 0, uMax: 0, vMax: 0, drawWidth: 0)
        let transparentBg = SIMD4<Float>(0, 0, 0, 0)
        let y = topPad + Float(row) * cellH

        // Background pass: merge contiguous cells with the same background
        // color into single wide quads to reduce instance/vertex count.
        var bgVerts: [Vertex] = []
        var col = 0
        var runStart = 0
        var runBg = defaultBg
        var lastBgHlId = -1
        var lastBgAttrs = CellAttributes()
        while col < cols {
            let cell = cells[col]
            let text = cell.text
            if text.isEmpty {
                // Double-width placeholder, skip
                col += 1
                continue
            }
            // Cache attribute lookup: skip dictionary access when hlId repeats
            if cell.hlId != lastBgHlId {
                lastBgHlId = cell.hlId
                lastBgAttrs = attributes[cell.hlId] ?? CellAttributes()
            }
            let bg = lastBgAttrs.effectiveBackground(defaultFg: defaultFg, defaultBg: defaultBg)
            let isDoubleWidth = col + 1 < cols && cells[col + 1].text.isEmpty
            let cellCount = isDoubleWidth ? 2 : 1

            if bg != runBg {
                // Flush previous run if it had a non-default background
                if runBg != defaultBg {
                    let x = Float(runStart) * cellW
                    let w = Float(col - runStart) * cellW
                    addQuad(
                        to: &bgVerts, x: x, y: y, w: w, h: cellH,
                        region: emptyRegion, bgColor: colorToSIMD4(runBg))
                }
                runStart = col
                runBg = bg
            }
            col += cellCount
        }
        // Flush final run
        if runBg != defaultBg {
            let x = Float(runStart) * cellW
            let w = Float(col - runStart) * cellW
            addQuad(
                to: &bgVerts, x: x, y: y, w: w, h: cellH,
                region: emptyRegion, bgColor: colorToSIMD4(runBg))
        }
        rowBackgroundVertices[row] = bgVerts

        // Foreground glyph pass with ligature support.
        // Groups consecutive same-attribute single-width cells into runs,
        // shapes each run via CoreText to detect font ligatures, then
        // emits vertices for each shaped glyph.
        var fgVerts: [Vertex] = []
        col = 0
        var lastFgHlId = -1
        var lastFgAttrs = CellAttributes()
        var lastFg = defaultFg
        while col < cols {
            let cell = cells[col]
            let text = cell.text

            if text.isEmpty || text == " " {
                col += 1
                continue
            }

            if cell.hlId != lastFgHlId {
                lastFgHlId = cell.hlId
                lastFgAttrs = attributes[cell.hlId] ?? CellAttributes()
                lastFg = lastFgAttrs.effectiveForeground(defaultFg: defaultFg, defaultBg: defaultBg)
            }

            let isDoubleWidth = col + 1 < cols && cells[col + 1].text.isEmpty

            if isDoubleWidth {
                let fgSIMD = colorToSIMD4(lastFg)
                let x = Float(col) * cellW
                let region = atlas.region(
                    text: text, font: font,
                    bold: lastFgAttrs.bold, italic: lastFgAttrs.italic,
                    cellSize: cellSize, cellCount: 2)
                // Multi-cell glyphs render at their natural advance so CJK
                // and wide ligatures keep their true aspect ratio regardless
                // of letter_spacing. The grid cursor still steps by 2 cells.
                let quadW = region.drawWidth * Float(atlas.scale)
                addQuad(
                    to: &fgVerts, x: x, y: y, w: quadW, h: cellH,
                    region: region, fgColor: fgSIMD, bgColor: transparentBg)
                col += 2
                continue
            }

            // Collect run of same-hlId single-width non-space non-empty cells
            let runStartCol = col
            let runHlId = cell.hlId
            var runEnd = col + 1
            while runEnd < cols {
                let c = cells[runEnd]
                if c.text.isEmpty || c.text == " " || c.hlId != runHlId { break }
                if runEnd + 1 < cols && cells[runEnd + 1].text.isEmpty { break }
                runEnd += 1
            }

            let fgSIMD = colorToSIMD4(lastFg)
            let runLen = runEnd - runStartCol

            // Shape for ligature detection
            let shaped: [ShapedGlyph]
            if runLen == 1 {
                shaped = [ShapedGlyph(text: text, colOffset: 0, cellCount: 1)]
            } else {
                var runText = ""
                for i in runStartCol..<runEnd { runText += cells[i].text }
                shaped = atlas.shapeRun(
                    runText, font: font,
                    bold: lastFgAttrs.bold, italic: lastFgAttrs.italic)
            }

            for glyph in shaped {
                let glyphCol = runStartCol + glyph.colOffset
                if glyph.cellCount >= 2 {
                    // Ligatures and contextual-alternate groups are laid on
                    // the grid, one quad per atlas segment, so a long group
                    // neither overruns the text after it nor exceeds the atlas.
                    for segment in atlas.segments(
                        text: glyph.text, font: font,
                        bold: lastFgAttrs.bold, italic: lastFgAttrs.italic,
                        cellSize: cellSize, cellCount: glyph.cellCount)
                    {
                        addQuad(
                            to: &fgVerts, x: Float(glyphCol + segment.colOffset) * cellW, y: y,
                            w: Float(segment.cellCount) * cellW, h: cellH,
                            region: segment.region, fgColor: fgSIMD, bgColor: transparentBg)
                    }
                    continue
                }
                let x = Float(glyphCol) * cellW
                let allocatedW = cellW * Float(glyph.cellCount)
                let region = atlas.region(
                    text: glyph.text, font: font,
                    bold: lastFgAttrs.bold, italic: lastFgAttrs.italic,
                    cellSize: cellSize, cellCount: glyph.cellCount)
                let glyphW = region.drawWidth * Float(atlas.scale)
                let quadW: Float
                if glyphW > allocatedW {
                    // Single-cell overflow (Nerd Font icons, italic tails):
                    // spill into the next cell only when it is empty space.
                    let nextCol = glyphCol + glyph.cellCount
                    let followedBySpace = nextCol < cols && cells[nextCol].text == " "
                    quadW = followedBySpace ? glyphW : allocatedW
                } else {
                    quadW = allocatedW
                }
                addQuad(
                    to: &fgVerts, x: x, y: y, w: quadW, h: cellH,
                    region: region, fgColor: fgSIMD, bgColor: transparentBg)
            }

            col = runEnd
        }
        rowForegroundVertices[row] = fgVerts
    }

    /// Ensure the slot's pre-allocated vertex buffer is large enough for the given vertex count.
    /// Grows by 2x when capacity is exceeded to amortize reallocation cost.
    private func ensureVertexBuffer(vertexCount: Int, slot: Int) -> MTLBuffer? {
        let requiredBytes = vertexCount * MemoryLayout<Vertex>.stride
        let capacity = vertexBuffers[slot]?.length ?? 0
        if let buffer = vertexBuffers[slot], capacity >= requiredBytes {
            return buffer
        }
        // Grow to at least 2x current capacity to avoid frequent reallocation
        let newCapacity = max(requiredBytes, capacity * 2)
        guard let buffer = device.makeBuffer(length: newCapacity, options: .storageModeShared)
        else {
            return nil
        }
        vertexBuffers[slot] = buffer
        return buffer
    }

    private func colorToSIMD4(_ rgb: Int) -> SIMD4<Float> {
        SIMD4<Float>(
            Float((rgb >> 16) & 0xFF) / 255.0,
            Float((rgb >> 8) & 0xFF) / 255.0,
            Float(rgb & 0xFF) / 255.0,
            1.0
        )
    }
}

enum MetalRendererError: Error {
    case noDevice
    case noCommandQueue
    case noLibrary
}
