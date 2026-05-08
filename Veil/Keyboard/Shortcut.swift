import AppKit

/// A parsed keyboard shortcut.
///
/// Created from a string like `"cmd+shift+n"` via `Shortcut.parse(_:)`.
/// Used for runtime event matching and NSMenu key equivalent conversion.
struct Shortcut: Equatable {
    let modifiers: NSEvent.ModifierFlags
    let key: Key

    /// The key portion of a shortcut, excluding modifiers.
    enum Key: Equatable {
        /// A single-character key like `a`, `1`, `,`, `/`, `` ` ``.
        /// Matched against `NSEvent.charactersIgnoringModifiers`.
        case character(String)

        /// A special key like `tab`, `f5`, `up`. Matched via keyCode or SpecialKey.
        case named(NamedKey)
    }

    /// Special keys that can't be expressed as a single character.
    enum NamedKey: String, CaseIterable {
        case tab, `return`, escape, space, backspace, delete, insert
        case up, down, left, right
        case home, end, pageUp = "pageup", pageDown = "pagedown"
        case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
        case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20
        case f21, f22, f23, f24, f25, f26, f27, f28, f29, f30
        case f31, f32, f33, f34, f35
    }
}

extension Shortcut {
    /// Parse a shortcut string like `"cmd+shift+n"` into a `Shortcut`.
    ///
    /// Returns `nil` for empty strings (interpreted by callers as "disabled")
    /// or malformed input.
    static func parse(_ string: String) -> Shortcut? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let tokens =
            trimmed
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !tokens.isEmpty else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        var keyTokens: [String] = []

        for token in tokens {
            let lower = token.lowercased()
            switch lower {
            case "cmd", "command":
                modifiers.insert(.command)
            case "ctrl", "control":
                modifiers.insert(.control)
            case "shift":
                modifiers.insert(.shift)
            case "alt", "option", "opt":
                modifiers.insert(.option)
            default:
                keyTokens.append(token)
            }
        }

        // Exactly one key token is required.
        guard keyTokens.count == 1 else { return nil }
        let keyToken = keyTokens[0]

        // Try named key first (case-insensitive).
        if let namedKey = NamedKey(rawValue: keyToken.lowercased()) {
            return Shortcut(modifiers: modifiers, key: .named(namedKey))
        }

        // Fall back to single-character key.
        guard keyToken.count == 1 else { return nil }
        return Shortcut(modifiers: modifiers, key: .character(keyToken))
    }
}

extension Shortcut {
    /// US ANSI shifted-punctuation pairs (unshifted → shifted). Used so that
    /// users can write either form in config (`shift+cmd+]` or `shift+cmd+}`)
    /// and both match the same physical keystroke. Cocoa's
    /// `charactersIgnoringModifiers` applies Shift to punctuation, so without
    /// this table only one form would work for any given pair.
    nonisolated private static let shiftedPunctuation: [Character: Character] = [
        "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
        "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
        "-": "_", "=": "+",
        "[": "{", "]": "}", "\\": "|",
        ";": ":", "'": "\"",
        ",": "<", ".": ">", "/": "?",
        "`": "~",
    ]

    /// Returns the unshifted form of a shifted-punctuation character (e.g.,
    /// `}` → `]`), or nil if the character has no shifted/unshifted pair.
    /// Used by `KeyUtils` to undo Cocoa's automatic Shift application on
    /// punctuation before forwarding to nvim, so mappings can be written
    /// with the physical-key form (`<S-D-]>` instead of `<S-D-}>`).
    nonisolated static func unshifted(_ character: Character) -> Character? {
        unshiftedPunctuation[character]
    }

    nonisolated private static let unshiftedPunctuation: [Character: Character] = {
        var reverse: [Character: Character] = [:]
        for (unshifted, shifted) in shiftedPunctuation {
            reverse[shifted] = unshifted
        }
        return reverse
    }()

    /// Returns true if the given keyboard event matches this shortcut.
    func matches(_ event: NSEvent) -> Bool {
        // Compare modifiers, ignoring .function, .numericPad, .capsLock, and
        // other flags Cocoa sets automatically but that aren't part of a shortcut.
        let relevantMask: NSEvent.ModifierFlags =
            [.command, .control, .option, .shift]
        let eventMods = event.modifierFlags.intersection(relevantMask)
        guard eventMods == self.modifiers else { return false }

        switch self.key {
        case .character(let c):
            guard let eventChars = event.charactersIgnoringModifiers else { return false }
            if eventChars.lowercased() == c.lowercased() { return true }
            // Accept the other side of the shifted-punctuation pair so that
            // `shift+cmd+]` and `shift+cmd+}` both match Shift+Cmd+].
            if modifiers.contains(.shift),
                let specChar = c.first, let eventChar = eventChars.first
            {
                if Self.shiftedPunctuation[specChar] == eventChar { return true }
                if Self.shiftedPunctuation[eventChar] == specChar { return true }
            }
            return false
        case .named(let namedKey):
            return matchesNamedKey(namedKey, event: event)
        }
    }

    private func matchesNamedKey(_ namedKey: NamedKey, event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers,
            let scalar = chars.unicodeScalars.first
        else { return false }
        let code = Int(scalar.value)

        switch namedKey {
        case .up: return code == NSUpArrowFunctionKey
        case .down: return code == NSDownArrowFunctionKey
        case .left: return code == NSLeftArrowFunctionKey
        case .right: return code == NSRightArrowFunctionKey
        case .home: return code == NSHomeFunctionKey
        case .end: return code == NSEndFunctionKey
        case .pageUp: return code == NSPageUpFunctionKey
        case .pageDown: return code == NSPageDownFunctionKey
        case .insert: return code == NSInsertFunctionKey
        case .delete: return code == NSDeleteFunctionKey
        case .tab: return code == 0x09
        case .return: return code == 0x0D
        case .escape: return code == 0x1B
        case .space: return code == 0x20
        case .backspace: return code == 0x7F
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
            .f21, .f22, .f23, .f24, .f25, .f26, .f27, .f28, .f29, .f30,
            .f31, .f32, .f33, .f34, .f35:
            guard let number = Int(namedKey.rawValue.dropFirst()) else { return false }
            return code == NSF1FunctionKey + (number - 1)
        }
    }
}

extension Shortcut {
    /// Convert to NSMenu's keyEquivalent + modifierMask form.
    ///
    /// For ASCII letters with Shift set, uses the uppercase letter and keeps
    /// `.shift` in the mask (unambiguous form). Digits and punctuation pass
    /// through verbatim — the caller is expected to write the shifted glyph
    /// directly (e.g., `cmd+shift+}`, not `cmd+shift+]`).
    ///
    /// Returns `nil` for named keys without a standard NSMenu representation.
    func toMenuKeyEquivalent() -> (String, NSEvent.ModifierFlags)? {
        switch self.key {
        case .character(let c):
            let hasShift = modifiers.contains(.shift)
            let isAsciiLetter =
                c.count == 1
                && c.unicodeScalars.first.map { $0.isASCII && $0.properties.isAlphabetic } == true
            let keyString = (hasShift && isAsciiLetter) ? c.uppercased() : c
            return (keyString, modifiers)
        case .named(let namedKey):
            return namedKey.menuCharacter.map { ($0, modifiers) }
        }
    }
}

extension Shortcut.NamedKey {
    /// The string NSMenu uses as `keyEquivalent` for this named key, if any.
    var menuCharacter: String? {
        switch self {
        case .tab: return "\t"
        case .return: return "\r"
        case .escape: return "\u{1B}"
        case .space: return " "
        case .backspace: return "\u{8}"
        case .delete: return "\u{7F}"
        case .up: return functionKeyString(NSUpArrowFunctionKey)
        case .down: return functionKeyString(NSDownArrowFunctionKey)
        case .left: return functionKeyString(NSLeftArrowFunctionKey)
        case .right: return functionKeyString(NSRightArrowFunctionKey)
        case .home: return functionKeyString(NSHomeFunctionKey)
        case .end: return functionKeyString(NSEndFunctionKey)
        case .pageUp: return functionKeyString(NSPageUpFunctionKey)
        case .pageDown: return functionKeyString(NSPageDownFunctionKey)
        case .insert: return functionKeyString(NSInsertFunctionKey)
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
            .f21, .f22, .f23, .f24, .f25, .f26, .f27, .f28, .f29, .f30,
            .f31, .f32, .f33, .f34, .f35:
            guard let number = Int(rawValue.dropFirst()) else { return nil }
            return functionKeyString(NSF1FunctionKey + (number - 1))
        }
    }

    private func functionKeyString(_ code: Int) -> String? {
        UnicodeScalar(code).map { String(Character($0)) }
    }
}
