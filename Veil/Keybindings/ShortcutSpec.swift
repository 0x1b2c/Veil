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
