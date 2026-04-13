import AppKit

/// A parsed keyboard shortcut specification.
///
/// Created from a string like `"cmd+shift+n"` via `ShortcutSpec.parse(_:)`.
/// Used for runtime event matching and NSMenu key equivalent conversion.
struct ShortcutSpec: Equatable {
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
        case tab, `return`, escape, space, backspace, delete
        case up, down, left, right
        case home, end, pageUp = "pageup", pageDown = "pagedown"
        case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
        case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20
    }
}

extension ShortcutSpec {
    /// Parse a shortcut string like `"cmd+shift+n"` into a `ShortcutSpec`.
    ///
    /// Returns `nil` for empty strings (interpreted by callers as "disabled")
    /// or malformed input.
    static func parse(_ string: String) -> ShortcutSpec? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let tokens = trimmed
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
            return ShortcutSpec(modifiers: modifiers, key: .named(namedKey))
        }

        // Fall back to single-character key.
        guard keyToken.count == 1 else { return nil }
        return ShortcutSpec(modifiers: modifiers, key: .character(keyToken))
    }
}
