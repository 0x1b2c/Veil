import Foundation
import TOML

// MARK: - DecodableDefault

/// Property wrapper that provides default values for missing keys during decoding.
/// Based on https://www.swiftbysundell.com/tips/default-decoding-values/
enum DecodableDefault {
    protocol Source {
        associatedtype Value: Decodable
        static var defaultValue: Value { get }
    }

    @propertyWrapper
    struct Wrapper<S: Source>: Decodable {
        typealias Value = S.Value
        var wrappedValue = S.defaultValue

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            wrappedValue = try container.decode(Value.self)
        }

        init() {}
    }
}

extension KeyedDecodingContainer {
    func decode<T>(
        _ type: DecodableDefault.Wrapper<T>.Type, forKey key: Key
    ) throws -> DecodableDefault.Wrapper<T> {
        try decodeIfPresent(type, forKey: key) ?? .init()
    }
}

// MARK: - Default value sources

extension DecodableDefault {
    enum True: Source { static var defaultValue: Bool { true } }
    enum False: Source { static var defaultValue: Bool { false } }
    enum EmptyString: Source { static var defaultValue: String { "" } }
    enum LineHeight: Source { static var defaultValue: CGFloat { 1.2 } }
    enum LetterSpacing: Source { static var defaultValue: CGFloat { 1.0 } }
    enum TitleBarBrightness: Source { static var defaultValue: CGFloat { -0.08 } }
    enum TabBarBrightness: Source { static var defaultValue: CGFloat { 0.05 } }
}

// MARK: - KeyAction

/// Identifies a Veil-owned action that can be bound to a keyboard shortcut.
enum KeyAction: String, CaseIterable {
    case newWindow = "new_window"
    case newWindowWithProfile = "new_window_with_profile"
    case closeTab = "close_tab"
    case closeWindow = "close_window"
    case quit
    case hide
    case minimize
    case toggleFullscreen = "toggle_fullscreen"
    case openSettings = "open_settings"
    case connectRemote = "connect_remote"

    /// The selector that this action's menu item uses. Used by AppDelegate's
    /// post-construction pass to locate the right menu item.
    ///
    /// We use `NSSelectorFromString` rather than `#selector(...)` because
    /// several of these selectors resolve to methods on classes that aren't
    /// visible from `Config.swift` (e.g., `NvimView.saveDocument`, or Cocoa's
    /// `NSApplication.terminate`). Using the string form keeps this file
    /// free of cross-module dependencies.
    var selector: Selector {
        switch self {
        case .newWindow: return NSSelectorFromString("newDocument:")
        case .newWindowWithProfile: return NSSelectorFromString("newDocumentWithProfilePicker:")
        case .closeTab: return NSSelectorFromString("closeTabOrWindow:")
        case .closeWindow: return NSSelectorFromString("closeWindow:")
        case .quit: return NSSelectorFromString("terminate:")
        case .hide: return NSSelectorFromString("hide:")
        case .minimize: return NSSelectorFromString("performMiniaturize:")
        case .toggleFullscreen: return NSSelectorFromString("toggleFullScreen:")
        case .openSettings: return NSSelectorFromString("openSettings:")
        case .connectRemote: return NSSelectorFromString("connectToRemote:")
        }
    }

    /// Built-in default shortcut string for this action.
    var defaultShortcut: String {
        switch self {
        case .newWindow: return "cmd+n"
        case .newWindowWithProfile: return "cmd+shift+n"
        case .closeTab: return "cmd+w"
        case .closeWindow: return "cmd+shift+w"
        case .quit: return "cmd+q"
        case .hide: return "cmd+h"
        case .minimize: return "cmd+m"
        case .toggleFullscreen: return "cmd+ctrl+f"
        case .openSettings: return "cmd+,"
        case .connectRemote: return "cmd+ctrl+shift+n"
        }
    }
}

// MARK: - RemoteEntry

struct RemoteEntry: Decodable {
    let name: String
    let address: String
}

// MARK: - VeilConfig

struct VeilConfig: Decodable {
    @DecodableDefault.Wrapper<DecodableDefault.LineHeight>
    var line_height: CGFloat
    @DecodableDefault.Wrapper<DecodableDefault.LetterSpacing>
    var letter_spacing: CGFloat
    @DecodableDefault.Wrapper<DecodableDefault.True>
    var ligatures: Bool
    @DecodableDefault.Wrapper<DecodableDefault.EmptyString>
    var nvim_path: String
    @DecodableDefault.Wrapper<DecodableDefault.EmptyString>
    var nvim_appname: String
    @DecodableDefault.Wrapper<DecodableDefault.False>
    var native_tabs: Bool
    @DecodableDefault.Wrapper<DecodableDefault.TitleBarBrightness>
    var titlebar_brightness_offset: CGFloat
    @DecodableDefault.Wrapper<DecodableDefault.TabBarBrightness>
    var tabbar_brightness_offset: CGFloat
    @DecodableDefault.Wrapper<DecodableDefault.True>
    var update_check: Bool

    var remote: [RemoteEntry]?

    static var current: VeilConfig = load()

    static func load() -> VeilConfig {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/veil/veil.toml")

        guard let data = try? String(contentsOf: configPath, encoding: .utf8) else {
            return VeilConfig()
        }

        do {
            return try TOMLDecoder().decode(VeilConfig.self, from: data)
        } catch {
            return VeilConfig()
        }
    }
}
