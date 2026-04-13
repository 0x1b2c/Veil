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

extension ShortcutSpec {
    /// Returns true if the given keyboard event matches this shortcut spec.
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
            return eventChars.lowercased() == c.lowercased()
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
        case .delete: return code == NSDeleteFunctionKey
        case .tab: return code == 0x09
        case .return: return code == 0x0D
        case .escape: return code == 0x1B
        case .space: return code == 0x20
        case .backspace: return code == 0x7F
        case .f1: return code == NSF1FunctionKey
        case .f2: return code == NSF2FunctionKey
        case .f3: return code == NSF3FunctionKey
        case .f4: return code == NSF4FunctionKey
        case .f5: return code == NSF5FunctionKey
        case .f6: return code == NSF6FunctionKey
        case .f7: return code == NSF7FunctionKey
        case .f8: return code == NSF8FunctionKey
        case .f9: return code == NSF9FunctionKey
        case .f10: return code == NSF10FunctionKey
        case .f11: return code == NSF11FunctionKey
        case .f12: return code == NSF12FunctionKey
        case .f13: return code == NSF13FunctionKey
        case .f14: return code == NSF14FunctionKey
        case .f15: return code == NSF15FunctionKey
        case .f16: return code == NSF16FunctionKey
        case .f17: return code == NSF17FunctionKey
        case .f18: return code == NSF18FunctionKey
        case .f19: return code == NSF19FunctionKey
        case .f20: return code == NSF20FunctionKey
        }
    }
}
