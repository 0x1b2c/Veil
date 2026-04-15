import AppKit
import MessagePack

// MARK: - Default Vim keymaps dispatch table

/// A default keymap entry: the shortcut spec and a closure that runs when matched.
/// The closure receives the matched NSEvent in case the dispatch needs information
/// from it (e.g., Cmd+1-9 uses the digit from the event).
///
/// The closure is `@MainActor`-isolated because `NvimView` is an `NSView` subclass
/// and therefore main-actor-bound. This matches how `performKeyEquivalent` itself
/// is invoked, so calling the closure from there is allowed without `await`.
private struct DefaultKeymapEntry {
    let spec: ShortcutSpec
    let dispatch: @MainActor (NvimView, NSEvent) -> Void
}

/// Default vim keymaps that are dispatched from performKeyEquivalent
/// (as opposed to via menu items). These are the ones that aren't owned
/// by any menu: Cmd+1-9, Ctrl+Tab, Shift+Ctrl+Tab, Shift+Cmd+{/}.
private let nonMenuDefaultKeymaps: [DefaultKeymapEntry] = {
    var entries: [DefaultKeymapEntry] = []

    // Cmd+1 through Cmd+8: switch to tab N.
    for digit in 1...8 {
        guard let spec = ShortcutSpec.parse("cmd+\(digit)") else { continue }
        entries.append(
            DefaultKeymapEntry(spec: spec) { view, _ in
                Task { try? await view.channel?.command("tabnext \(digit)") }
            })
    }

    // Cmd+9: switch to last tab.
    if let spec = ShortcutSpec.parse("cmd+9") {
        entries.append(
            DefaultKeymapEntry(spec: spec) { view, _ in
                Task { try? await view.channel?.command("tablast") }
            })
    }

    // Ctrl+Tab: next tab.
    if let spec = ShortcutSpec.parse("ctrl+tab") {
        entries.append(
            DefaultKeymapEntry(spec: spec) { view, _ in
                Task { try? await view.channel?.command("tabnext") }
            })
    }

    // Shift+Ctrl+Tab: previous tab.
    if let spec = ShortcutSpec.parse("shift+ctrl+tab") {
        entries.append(
            DefaultKeymapEntry(spec: spec) { view, _ in
                Task { try? await view.channel?.command("tabprevious") }
            })
    }

    // Shift+Cmd+}: next tab. (Note: the user presses Shift+Cmd+] which
    // produces `}` via Cocoa's shifted-punctuation behavior.)
    if let spec = ShortcutSpec.parse("shift+cmd+}") {
        entries.append(
            DefaultKeymapEntry(spec: spec) { view, _ in
                Task { try? await view.channel?.command("tabnext") }
            })
    }

    // Shift+Cmd+{: previous tab. (User presses Shift+Cmd+[.)
    if let spec = ShortcutSpec.parse("shift+cmd+{") {
        entries.append(
            DefaultKeymapEntry(spec: spec) { view, _ in
                Task { try? await view.channel?.command("tabprevious") }
            })
    }

    return entries
}()

// MARK: - Keyboard handling

extension NvimView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let keys = VeilConfig.current.keysOrDefault

        // Step 1: non-menu default keymaps. Always matched, because macOS's
        //         key view loop swallows Ctrl+Tab before it reaches keyDown,
        //         so we must claim it here in both modes. When
        //         bind_default_keymaps is true, run the vim command (tabnext
        //         etc.). When false, forward the raw key to nvim (<C-Tab>,
        //         <D-1>, <S-D-}>, ...) so user mappings on those keys fire.
        for entry in nonMenuDefaultKeymaps {
            if entry.spec.matches(event) {
                if keys.bind_default_keymaps {
                    entry.dispatch(self, event)
                } else {
                    sendKeyDirectly(event)
                }
                return true
            }
        }

        // Step 2: NSView's default subview walk. This rarely claims anything
        //         in Veil (the text area has no interactive subviews), but
        //         we honor the contract.
        if super.performKeyEquivalent(with: event) {
            return true
        }

        // Step 3: let the main menu handle it. Cocoa's event routing consults
        //         NvimView.performKeyEquivalent BEFORE the menu bar, so if we
        //         return true here without asking the menu, Cmd+Q, Cmd+N,
        //         Cmd+S and every other menu-bound shortcut never reaches
        //         its action. Explicitly invoke the menu's performKeyEquivalent
        //         so menu items with matching keyEquivalents can fire.
        //         This also handles Cmd+` via macOS's auto-injected Window
        //         menu cycling (`systemMenu="window"` in the xib).
        if let mainMenu = NSApp.mainMenu,
            mainMenu.performKeyEquivalent(with: event)
        {
            return true
        }

        // Step 4: Cmd+letter synthesis fallback.
        //         Cocoa does NOT naturally deliver Cmd+letter events to
        //         keyDown, so this branch synthesizes <D-letter> / <D-1> /
        //         <S-D-}> etc. for any Cmd+ event that no menu claimed.
        //         This is how Cmd+P, Cmd+J, and any unbound Cmd+letter
        //         reach nvim. Also how disabled default keymaps reach nvim
        //         when bind_default_keymaps = false — the menu items have
        //         cleared keyEquivalents, so step 3 above won't claim them
        //         and they fall through here.
        if event.modifierFlags.contains(.command),
            let chars = event.charactersIgnoringModifiers,
            !chars.isEmpty,
            chars != "`"
        {
            let nvimKey = KeyUtils.nvimKey(
                characters: chars, modifiers: event.modifierFlags)
            Task { await channel?.send(key: nvimKey) }
            return true
        }

        // Step 5: non-Cmd events fall through. Ctrl+Tab, F-keys, arrow
        //         keys, etc. become regular keyDown: calls in the next
        //         event dispatch stage.
        return false
    }

    override func keyDown(with event: NSEvent) {
        // When composing (marked text active), all keys go through IME
        // so backspace shortens the pinyin, Enter confirms, Esc cancels, etc.
        if markedText != nil {
            inputContext?.handleEvent(event)
            return
        }

        let modifiers = event.modifierFlags.intersection([.control, .option, .command])
        if !modifiers.isEmpty {
            sendKeyDirectly(event)
            return
        }

        // Special keys bypass IME — they would otherwise be consumed by doCommand(by:)
        if let chars = event.characters, let scalar = chars.unicodeScalars.first {
            let code = Int(scalar.value)
            if code == 0x1B || code == 0x0D || code == 0x09 || code == 0x7F
                || code == 0x19 || (code >= 0xF700 && code <= 0xF8FF)
            {
                sendKeyDirectly(event)
                return
            }
        }

        // Normal text goes through IME
        keyDownDone = false
        inputContext?.handleEvent(event)
        if !keyDownDone && markedText == nil {
            sendKeyDirectly(event)
            keyDownDone = true
        }
    }

    private func sendKeyDirectly(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.control, .option, .command])
        let chars: String?
        if !modifiers.isEmpty {
            chars = event.charactersIgnoringModifiers
        } else {
            chars = event.characters
        }
        guard let characters = chars, !characters.isEmpty else { return }
        let nvimKey = KeyUtils.nvimKey(characters: characters, modifiers: event.modifierFlags)
        guard !nvimKey.isEmpty else { return }
        Task { await channel?.send(key: nvimKey) }
    }

    func updateMarkedTextDisplay() {
        guard let text = markedText, !text.isEmpty else {
            clearMarkedText()
            return
        }

        let originX = CGFloat(markedPosition.col) * cellSize.width
        let originY =
            bounds.height - CGFloat(markedPosition.row + 1) * cellSize.height
            - Self.gridTopPadding
        let screenScale = window?.backingScaleFactor ?? 2.0

        // Compute cell counts per character (CJK = 2, others = 1)
        let chars = Array(text)
        let cellCounts = chars.map { cellWidth(of: $0) }
        let totalCells = cellCounts.reduce(0, +)
        let cursorWidth: CGFloat = 2
        let textWidth = cellSize.width * CGFloat(totalCells)
        let width = textWidth + cursorWidth
        let height = cellSize.height

        let pixelWidth = Int(ceil(width * screenScale))
        let pixelHeight = Int(ceil(height * screenScale))
        guard pixelWidth > 0, pixelHeight > 0 else { return }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let ctx = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return }

        ctx.scaleBy(x: screenScale, y: screenScale)

        // Fill background
        ctx.setFillColor(NSColor(rgb: defaultBg).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Render each character using GlyphCache (same pipeline as grid)
        let attrs = CellAttributes()
        var xOffset: CGFloat = 0
        for (i, char) in chars.enumerated() {
            let count = cellCounts[i]
            let charWidth = cellSize.width * CGFloat(count)
            let cached = glyphCache.get(
                text: String(char), attrs: attrs,
                defaultFg: defaultFg, defaultBg: defaultBg, cellCount: count
            )
            // Multi-cell glyphs draw at their natural advance to match the
            // grid renderer; the xOffset still advances by full cell width
            // so IME caret position stays aligned to the grid.
            let drawWidth = count >= 2 ? cached.drawWidth : charWidth
            let cellRect = CGRect(x: xOffset, y: 0, width: drawWidth, height: height)
            ctx.draw(cached.image, in: cellRect)
            xOffset += charWidth
        }

        // Draw underline at bottom (under text only, not cursor)
        let underlineY: CGFloat = 1.5
        ctx.setStrokeColor(NSColor(rgb: defaultFg).cgColor)
        ctx.setLineWidth(1.0)
        ctx.move(to: CGPoint(x: 0, y: underlineY))
        ctx.addLine(to: CGPoint(x: textWidth, y: underlineY))
        ctx.strokePath()

        // Draw cursor line at the right edge of the marked text
        ctx.setFillColor(NSColor(rgb: defaultFg).cgColor)
        ctx.fill(CGRect(x: textWidth, y: 0, width: cursorWidth, height: height))

        guard let image = ctx.makeImage() else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        markedLayer.contents = image
        markedLayer.contentsScale = screenScale
        markedLayer.frame = CGRect(
            x: originX,
            y: originY,
            width: width,
            height: height
        )
        markedLayer.isHidden = false
        CATransaction.commit()
    }

    func clearMarkedText() {
        markedText = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        markedLayer.isHidden = true
        markedLayer.contents = nil
        CATransaction.commit()
    }
    // MARK: - Debug Overlay

    @objc func toggleDebugOverlay(_ sender: Any?) {
        debugOverlayEnabled.toggle()
        delegate?.nvimViewNeedsDisplay(self)
    }

    // MARK: - Standard File actions

    @objc func saveDocument(_ sender: Any?) {
        Task { try? await channel?.command("w") }
    }

    @objc func closeTabOrWindow(_ sender: Any?) {
        Task {
            guard let channel else { return }
            let (_, result) = await channel.request(
                "nvim_eval", params: [.string("tabpagenr('$')")])
            let tabCount = result.intValue
            if tabCount > 1 {
                try? await channel.command("tabclose")
            } else {
                await MainActor.run {
                    self.window?.performClose(nil)
                }
            }
        }
    }

    @objc func closeWindow(_ sender: Any?) {
        window?.performClose(nil)
    }

    // MARK: - Standard Edit actions

    @objc func undo(_ sender: Any?) {
        Task { await channel?.send(key: "u") }
    }

    @objc func redo(_ sender: Any?) {
        Task { await channel?.send(key: "<C-r>") }
    }

    @objc func cut(_ sender: Any?) {
        Task { await channel?.send(key: "\"+d") }
    }

    @objc func copy(_ sender: Any?) {
        Task { await channel?.send(key: "\"+y") }
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        Task {
            _ = await channel?.request(
                "nvim_paste", params: [.string(text), .bool(true), .int(-1)])
        }
    }

    override func selectAll(_ sender: Any?) {
        Task { await channel?.send(key: "ggVG") }
    }
}

// MARK: - NSTextInputClient

extension NvimView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        keyDownDone = true
        clearMarkedText()

        let text: String
        if let attrString = string as? NSAttributedString {
            text = attrString.string
        } else if let str = string as? String {
            text = str
        } else {
            return
        }

        // Send each character as a Neovim key
        for char in text {
            let nvimKey = KeyUtils.nvimKey(characters: String(char), modifiers: [])
            Task { await channel?.send(key: nvimKey) }
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text: String
        if let attrString = string as? NSAttributedString {
            text = attrString.string
        } else if let str = string as? String {
            text = str
        } else {
            return
        }

        if text.isEmpty {
            clearMarkedText()
        } else {
            markedText = text
            // Capture cursor position when composition begins
            markedPosition = gridPosition(
                for: NSPoint(
                    x: cursorLayer.frame.origin.x,
                    y: cursorLayer.frame.origin.y + cellSize.height / 2
                ))
            updateMarkedTextDisplay()
        }
    }

    func unmarkText() {
        clearMarkedText()
        inputContext?.discardMarkedText()
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        guard let text = markedText else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: text.utf16.count)
    }

    func hasMarkedText() -> Bool {
        markedText != nil
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?)
        -> NSAttributedString?
    {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Return the cursor position in screen coordinates for IME candidate window
        guard let windowObj = window else { return .zero }
        let cursorFrame = cursorLayer.frame
        let viewRect = convert(cursorFrame, to: nil)
        return windowObj.convertToScreen(viewRect)
    }

    func characterIndex(for point: NSPoint) -> Int {
        let viewPoint = convert(point, from: nil)
        let pos = gridPosition(for: viewPoint)

        guard pos.row >= 0, pos.row < flatCharIndices.count else {
            return NSNotFound
        }
        let rowIndices = flatCharIndices[pos.row]
        guard pos.col >= 0, pos.col < rowIndices.count else {
            return NSNotFound
        }
        return rowIndices[pos.col]
    }

    override func doCommand(by selector: Selector) {
        keyDownDone = true
        // Most commands are handled by Neovim
    }

    /// Return cell count for a character by measuring its glyph advance.
    private func cellWidth(of char: Character) -> Int {
        let ctFont = gridFont as CTFont
        var chars = Array(String(char).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(ctFont, &chars, &glyphs, chars.count) else {
            return 1
        }
        let advance = CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyphs, nil, glyphs.count)
        return advance > Double(cellSize.width) * 1.5 ? 2 : 1
    }
}
