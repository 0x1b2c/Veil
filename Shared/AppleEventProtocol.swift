import AppKit

// Cross-process protocol between the bundled CLI and the GUI process.
// Keep constants and Codable schemas here; caller-specific send/timeout
// behavior stays in the CLI or AppDelegate.
enum VeilAppleEventProtocol {
    static let eventClass = AEEventClass(bitPattern: fourCharCode("Veil"))
    static let openEventID = AEEventID(bitPattern: fourCharCode("Open"))
    static let jsonParamKey = AEKeyword(bitPattern: fourCharCode("json"))
    static let replyTimeout: TimeInterval = 5

    private static func fourCharCode(_ s: String) -> Int32 {
        let chars = Array(s.utf8)
        return Int32(chars[0]) << 24
            | Int32(chars[1]) << 16
            | Int32(chars[2]) << 8
            | Int32(chars[3])
    }
}

struct VeilOpenRequest: Codable {
    var nvimArgs: [String]
    var env: [String: String]?
    var renderer: VeilRendererOption?
    var nvimAppName: String?
}

struct VeilOpenReply: Codable {
    var ok: Bool
    var message: String?
}
