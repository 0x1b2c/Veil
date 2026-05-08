import AppKit

nonisolated enum KeyUtils {
    static func nvimKey(characters: String, modifiers: NSEvent.ModifierFlags) -> String {
        // Cocoa's `charactersIgnoringModifiers` applies Shift to punctuation,
        // so Shift+] arrives as `}`. Whenever Shift is in the modifier set,
        // translate back to the unshifted form so the key string Veil sends
        // matches physical-key intuition (`<S-D-]>` rather than `<S-D-}>`) and
        // lines up with how nvim mappings are usually written. In practice the
        // call sites that reach this function with Shift always pair it with
        // Ctrl/Option/Cmd; plain Shift+punctuation typing goes through IME and
        // never reaches `nvimKey`.
        let resolvedCharacters: String = {
            guard modifiers.contains(.shift),
                characters.count == 1,
                let first = characters.first,
                let unshifted = Shortcut.unshifted(first)
            else { return characters }
            return String(unshifted)
        }()

        guard let scalar = resolvedCharacters.unicodeScalars.first else { return "" }
        let code = Int(scalar.value)

        if let name = specialKeyName(code) {
            return wrapWithModifiers(name, modifiers: modifiers)
        }
        if code == 0x1B { return wrapWithModifiers("Esc", modifiers: modifiers) }
        if code == 0x7F { return wrapWithModifiers("BS", modifiers: modifiers) }
        if code == 0x09 { return wrapWithModifiers("Tab", modifiers: modifiers) }
        if code == 0x0D { return wrapWithModifiers("CR", modifiers: modifiers) }
        if code == 0x20 { return wrapWithModifiers("Space", modifiers: modifiers) }
        if resolvedCharacters == "<" { return wrapWithModifiers("lt", modifiers: modifiers) }
        if resolvedCharacters == "\\" { return wrapWithModifiers("Bslash", modifiers: modifiers) }

        let relevantModifiers = modifiers.intersection([.control, .option, .command, .shift])
        if relevantModifiers.isEmpty { return resolvedCharacters }
        return wrapWithModifiers(resolvedCharacters, modifiers: modifiers)
    }

    private static func wrapWithModifiers(_ key: String, modifiers: NSEvent.ModifierFlags) -> String
    {
        var prefix = ""
        if modifiers.contains(.control) { prefix += "C-" }
        if modifiers.contains(.shift) { prefix += "S-" }
        if modifiers.contains(.option) { prefix += "M-" }
        if modifiers.contains(.command) { prefix += "D-" }
        if prefix.isEmpty && key.count == 1 && !isNamedKey(key) { return key }
        return "<\(prefix)\(key)>"
    }

    private static func isNamedKey(_ key: String) -> Bool {
        ["lt", "Bslash", "Space", "CR", "Tab", "Esc", "BS"].contains(key)
    }

    private static func specialKeyName(_ code: Int) -> String? { specialKeys[code] }

    private static let specialKeys: [Int: String] = {
        var map: [Int: String] = [
            NSUpArrowFunctionKey: "Up",
            NSDownArrowFunctionKey: "Down",
            NSLeftArrowFunctionKey: "Left",
            NSRightArrowFunctionKey: "Right",
            NSInsertFunctionKey: "Insert",
            NSDeleteFunctionKey: "Del",
            NSHomeFunctionKey: "Home",
            NSEndFunctionKey: "End",
            NSPageUpFunctionKey: "PageUp",
            NSPageDownFunctionKey: "PageDown",
        ]
        for i in 0..<35 { map[NSF1FunctionKey + i] = "F\(i + 1)" }
        return map
    }()
}
