import Foundation

/// Decides where the human who issued the current command is sitting.
///
/// A wezterm mux pane is client-agnostic: the same shell can be viewed from
/// several attached GUI clients at once, so no environment variable can say
/// who is watching. What the mux does know is which client's keyboard was
/// used last — the client whose `idle_time` is smallest at the moment the
/// command runs is the one that just typed it.
public enum WorkspaceViewer {
    public struct Client: Decodable, Equatable {
        public struct Idle: Decodable, Equatable {
            public var secs: UInt64
            public var nanos: UInt32

            public init(secs: UInt64, nanos: UInt32) {
                self.secs = secs
                self.nanos = nanos
            }
        }

        public var hostname: String
        public var idleTime: Idle

        enum CodingKeys: String, CodingKey {
            case hostname
            case idleTime = "idle_time"
        }

        public init(hostname: String, idleTime: Idle) {
            self.hostname = hostname
            self.idleTime = idleTime
        }
    }

    public enum Location: Equatable {
        case local
        case remote(host: String)
    }

    /// wezterm decorates non-local client hostnames ("A2.local (via proxy
    /// pid 13754)") and macOS reports the local host as "2B" or "2B.local"
    /// depending on the API. Reduce both to a comparable core: cut at the
    /// first space or "(", lowercase, drop a trailing ".local".
    public static func normalize(hostname: String) -> String {
        var core = hostname
        if let cut = core.firstIndex(where: { $0 == " " || $0 == "(" }) {
            core = String(core[..<cut])
        }
        core = core.trimmingCharacters(in: .whitespaces).lowercased()
        if core.hasSuffix(".local") {
            core.removeLast(".local".count)
        }
        return core
    }

    /// Where the freshest-input client of `wezterm cli list-clients
    /// --format json` sits relative to this machine. Returns nil when the
    /// answer cannot be determined (unparseable or empty client list);
    /// callers must then fall back to plain local behavior.
    public static func location(
        ofFreshestClientIn json: Data, localHostname: String
    ) -> Location? {
        guard let clients = try? JSONDecoder().decode([Client].self, from: json),
            let freshest = clients.min(by: {
                ($0.idleTime.secs, $0.idleTime.nanos) < ($1.idleTime.secs, $1.idleTime.nanos)
            })
        else { return nil }
        let host = normalize(hostname: freshest.hostname)
        return host == normalize(hostname: localHostname) ? .local : .remote(host: host)
    }
}

/// Schema of `~/.local/state/veil/registry.json`, the per-host table of
/// headless workspace servers: `{ "<project root>": {port, pid} }`. The pid
/// is recorded for reaping only — liveness is always a socket probe, never
/// a pid check (pids get reused, and a live pid says nothing about the
/// listen socket).
public enum WorkspaceRegistry {
    public struct Entry: Codable, Equatable {
        public var port: Int
        public var pid: Int32

        public init(port: Int, pid: Int32) {
            self.port = port
            self.pid = pid
        }
    }

    public typealias Table = [String: Entry]

    /// A corrupt or empty registry heals to an empty table; every entry is
    /// re-creatable by spawning a fresh server.
    public static func decode(_ data: Data) -> Table {
        (try? JSONDecoder().decode(Table.self, from: data)) ?? [:]
    }

    public static func encode(_ table: Table) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(table)
    }
}

/// The OSC 1337 user var a workspace host emits after preparing a server.
/// wezterm's mux protocol broadcasts it to every attached GUI client; the
/// `user-var-changed` handler on the machine named by `viewer` reacts by
/// running `veil --connect <host>:<port> --workspace <workspace>`.
public enum WorkspaceUserVar {
    public static let name = "veil-edit"

    public struct Payload: Codable, Equatable {
        public var host: String
        public var port: Int
        public var workspace: String
        /// Normalized hostname of the machine whose keyboard issued the
        /// command; handlers on other machines ignore the broadcast.
        public var viewer: String

        public init(host: String, port: Int, workspace: String, viewer: String) {
            self.host = host
            self.port = port
            self.workspace = workspace
            self.viewer = viewer
        }
    }

    public static func sequence(for payload: Payload) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let json = try? encoder.encode(payload) else { return nil }
        return "\u{1B}]1337;SetUserVar=\(name)=\(json.base64EncodedString())\u{07}"
    }
}
