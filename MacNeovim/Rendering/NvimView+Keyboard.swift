import AppKit

// MARK: - Keyboard handling

extension NvimView {
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.control, .option, .command])
        if !modifiers.isEmpty {
            // Meta modifiers present: bypass IME, send directly
            guard let characters = event.characters else { return }
            let nvimKey = KeyUtils.nvimKey(characters: characters, modifiers: event.modifierFlags)
            guard !nvimKey.isEmpty else { return }
            Task { await channel?.send(key: nvimKey) }
        } else {
            // Let the input context handle it (IME path)
            inputContext?.handleEvent(event)
        }
    }
}

// MARK: - NSTextInputClient

extension NvimView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
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
        // Stub for Task 11 (full IME support)
    }

    func unmarkText() {
        // Stub for Task 11
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        false
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
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
        NSNotFound
    }

    override func doCommand(by selector: Selector) {
        // Stub: most commands are handled by Neovim
    }
}
