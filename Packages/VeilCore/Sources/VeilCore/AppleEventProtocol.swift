import AppKit

// Cross-process protocol between the bundled CLI and the GUI process.
// Keep constants and Codable schemas here; caller-specific send/timeout
// behavior stays in the CLI or AppDelegate.
public enum VeilAppleEventProtocol {
    public static let eventClass = AEEventClass(bitPattern: fourCharCode("Veil"))
    public static let openEventID = AEEventID(bitPattern: fourCharCode("Open"))
    public static let jsonParamKey = AEKeyword(bitPattern: fourCharCode("json"))
    public static let replyTimeout: TimeInterval = 5

    private static func fourCharCode(_ s: String) -> Int32 {
        let chars = Array(s.utf8)
        return Int32(chars[0]) << 24
            | Int32(chars[1]) << 16
            | Int32(chars[2]) << 8
            | Int32(chars[3])
    }
}

public struct VeilOpenRequest: Codable {
    public var nvimArgs: [String]
    public var env: [String: String]?
    public var renderer: VeilRendererOption?
    public var nvimAppName: String?

    public init(
        nvimArgs: [String],
        env: [String: String]? = nil,
        renderer: VeilRendererOption? = nil,
        nvimAppName: String? = nil
    ) {
        self.nvimArgs = nvimArgs
        self.env = env
        self.renderer = renderer
        self.nvimAppName = nvimAppName
    }
}

public struct VeilOpenReply: Codable {
    public var ok: Bool
    public var message: String?

    public init(ok: Bool, message: String? = nil) {
        self.ok = ok
        self.message = message
    }
}
