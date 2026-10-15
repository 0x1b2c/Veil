import Foundation

/// Decides where the human who issued the current command is sitting.
///
/// A wezterm mux pane is client-agnostic: the same shell can be viewed from
/// several attached GUI clients at once, so no environment variable can say
/// who is watching. What the mux does know is which client's keyboard was
/// used last: the client whose `idle_time` is smallest at the moment the
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

    /// The keystroke that launched this command is itself client input, so
    /// in any genuine invocation the winning client's idle time is near
    /// zero. A stale winner means nobody just typed this (say, a script in
    /// a pane firing long after the last human input), and the detection
    /// result cannot be trusted.
    static let maxTrustedRemoteIdleSecs: UInt64 = 5

    /// wezterm decorates non-local client hostnames ("A2.local (via proxy
    /// pid 13754)") and the same machine may report itself as "2B",
    /// "2B.local", or a FQDN like "2b.tail1234.ts.net" depending on the
    /// API. Compare first labels only: cut at the first space, "(", or ".",
    /// then lowercase.
    public static func normalize(hostname: String) -> String {
        var core = hostname
        if let cut = core.firstIndex(where: { $0 == " " || $0 == "(" || $0 == "." }) {
            core = String(core[..<cut])
        }
        return core.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// This machine's name as `gethostname()` reports it, which is the
    /// same source wezterm reads for the client metadata compared above.
    ///
    /// Deliberately not `ProcessInfo.hostName`: that one comes from
    /// SystemConfiguration's LocalHostName, a different name that a Mac
    /// with a customized computer name sets independently. A host whose
    /// `gethostname()` is "2B" can report "example-mac.local" there,
    /// and the comparison then never matches, so the machine the user is
    /// sitting at looks remote to itself.
    ///
    /// nil when the call fails, which callers must read as "cannot tell"
    /// rather than "not this machine".
    public static func localHostname() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard gethostname(&buffer, buffer.count - 1) == 0 else { return nil }
        buffer[buffer.count - 1] = 0
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }

    /// Where the freshest-input client of `wezterm cli list-clients
    /// --format json` sits relative to this machine. Returns nil when the
    /// answer cannot be determined (unparseable or empty client list, or a
    /// remote winner whose idle time exceeds the trust threshold); callers
    /// must then fall back to plain local behavior. A local winner needs no
    /// threshold; falling back would mean the same thing.
    public static func location(
        ofFreshestClientIn json: Data, localHostname: String
    ) -> Location? {
        guard let clients = try? JSONDecoder().decode([Client].self, from: json),
            let freshest = clients.min(by: {
                ($0.idleTime.secs, $0.idleTime.nanos) < ($1.idleTime.secs, $1.idleTime.nanos)
            })
        else { return nil }
        let host = normalize(hostname: freshest.hostname)
        if host == normalize(hostname: localHostname) { return .local }
        guard freshest.idleTime.secs < maxTrustedRemoteIdleSecs else { return nil }
        return .remote(host: host)
    }
}

/// Schema of `~/.local/state/veil/registry.json`, the per-host table of
/// headless workspace servers: `{ "<project root>": {port, pid} }`.
///
/// Liveness is the pid, not the socket: an nvim blocked in `system()`, `:!cmd`
/// or a long Lua loop stops answering RPC while still holding the user's
/// unsaved buffers, so a silent socket only means "cannot take a command
/// right now". A server is gone only when its pid no longer runs our nvim
/// for that address, either because the process exited or because the pid
/// was reused; only then may its entry be dropped. See `serverState`.
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

    /// Where a registered server stands. The raw value is the label
    /// `veil --workspaces` prints.
    public enum ServerState: String, Equatable {
        /// Answers RPC; files can be sent to it.
        case alive
        /// Still running but not answering, typically blocked on a
        /// long-running command. Must be left alone: it may hold unsaved work.
        case busy
        /// The recorded pid is gone or now belongs to another program.
        case dead
    }

    /// - Parameters:
    ///   - answersProbe: whether the server answered an RPC at `addr`.
    ///   - commandLine: `ps -o command=` of the entry's pid, nil when no
    ///     such process exists.
    ///   - addr: the `host:port` the server was spawned to listen on.
    public static func serverState(
        answersProbe: Bool, commandLine: String?, addr: String
    ) -> ServerState {
        if answersProbe { return .alive }
        guard let commandLine, isServerCommand(commandLine, listeningOn: addr) else {
            return .dead
        }
        return .busy
    }

    /// Whether `commandLine` is an nvim listening on exactly `addr`. argv[0]
    /// shows as a full path (`/opt/homebrew/bin/nvim`) even though the
    /// server is spawned as bare `nvim`, so only its last component counts.
    private static func isServerCommand(_ commandLine: String, listeningOn addr: String) -> Bool {
        let words = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let program = words.first,
            URL(fileURLWithPath: program).lastPathComponent == "nvim",
            let listen = words.firstIndex(of: "--listen"),
            listen + 1 < words.count
        else { return false }
        return words[listen + 1] == addr
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
