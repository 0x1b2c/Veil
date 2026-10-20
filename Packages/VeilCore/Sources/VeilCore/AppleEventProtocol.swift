import AppKit

// Cross-process protocol between the bundled CLI and the GUI process.
// Keep constants and Codable schemas here; caller-specific send/timeout
// behavior stays in the CLI or AppDelegate.
public enum VeilAppleEventProtocol {
    public static let eventClass = AEEventClass(bitPattern: fourCharCode("Veil"))
    public static let openEventID = AEEventID(bitPattern: fourCharCode("Open"))
    public static let jsonParamKey = AEKeyword(bitPattern: fourCharCode("json"))
    public static let replyTimeout: TimeInterval = 5

    /// What to tell the user when macOS or Veil.app answers an open request
    /// with `status`. A missing Automation grant is the common case: macOS
    /// attributes the CLI's Apple Events to the app it runs under, normally
    /// the terminal, and refuses delivery until the user allows that app to
    /// control Veil.
    public static func failureMessage(forStatus status: OSStatus) -> String {
        switch Int(status) {
        case errAEEventNotPermitted, errAEEventWouldRequireUserConsent:
            return "macOS has not allowed this terminal to control Veil. Allow it in "
                + "System Settings > Privacy & Security > Automation, then run the command again."
        default:
            return "Veil.app did not accept the request (Apple Event error \(status))."
        }
    }

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
    /// Remote nvim address ("host:port") for scriptable connections
    /// (CLI --veil-connect). When set, the GUI connects or activates the
    /// window for this address instead of opening a local window.
    public var remoteAddress: String?
    /// Workspace name (the project root's last path component, `~` for
    /// the home workspace) identifying the remote instance; used for
    /// window titling.
    public var workspace: String?

    public init(
        nvimArgs: [String],
        env: [String: String]? = nil,
        renderer: VeilRendererOption? = nil,
        nvimAppName: String? = nil,
        remoteAddress: String? = nil,
        workspace: String? = nil
    ) {
        self.nvimArgs = nvimArgs
        self.env = env
        self.renderer = renderer
        self.nvimAppName = nvimAppName
        self.remoteAddress = remoteAddress
        self.workspace = workspace
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
