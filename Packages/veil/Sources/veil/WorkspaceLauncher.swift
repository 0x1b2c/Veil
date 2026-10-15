import Foundation
import VeilCore

/// Server-side half of the remote workspace flow. When the human behind
/// this command sits on another machine (per wezterm's client metadata),
/// the CLI does not open a local window: it keeps one headless
/// `nvim --headless --listen` per project root (tracked in the registry),
/// sends the requested files into it, and broadcasts a user var telling
/// the viewer's machine to attach a Veil window via `veil --connect`.
enum WorkspaceLauncher {
    // MARK: - Viewer detection

    /// Normalized hostname of the remote machine whose keyboard issued
    /// this command, or nil when the viewer is local or undeterminable
    /// (not in a wezterm pane, `wezterm cli` failed, unparseable output).
    /// nil means: behave exactly as before this feature existed.
    static func remoteViewerHost() -> String? {
        guard ProcessInfo.processInfo.environment["WEZTERM_UNIX_SOCKET"] != nil else {
            return nil
        }
        guard
            let result = runCapture(
                "/usr/bin/env", ["wezterm", "cli", "list-clients", "--format", "json"],
                timeout: 2),
            result.status == 0,
            let localHostname = WorkspaceViewer.localHostname(),
            case .remote(let host) = WorkspaceViewer.location(
                ofFreshestClientIn: result.stdout,
                localHostname: localHostname) ?? .local
        else { return nil }
        return host
    }

    // MARK: - Main flows

    static func summon(nvimArgs: [String], viewer: String) -> Bool {
        let (root, name) = resolveWorkspaceRoot()
        let host = listenHost()
        var table = loadRegistry()

        var port: Int
        let entry = table[root]
        let state = entry.map { serverState(of: $0, addr: "\(host):\($0.port)") } ?? .dead
        if let entry, state == .alive {
            port = entry.port
        } else if let entry, state == .busy {
            reportBusy(name: name, entry: entry, addr: "\(host):\(entry.port)")
            return false
        } else {
            // Gone, or its pid now runs something else: forget the entry
            // without signaling anything.
            table[root] = nil
            guard let picked = pickPort(host: host, table: table) else {
                fputs("veil: no free workspace port in \(portRange)\n", stderr)
                return false
            }
            guard let pid = spawnServer(root: root, name: name, addr: "\(host):\(picked)") else {
                return false
            }
            port = picked
            table[root] = .init(port: port, pid: pid)
            saveRegistry(table)
        }

        guard sendFiles(nvimArgs, to: "\(host):\(port)") else { return false }
        let payload = WorkspaceUserVar.Payload(
            host: host, port: port, workspace: name, viewer: viewer)
        guard let sequence = WorkspaceUserVar.sequence(for: payload),
            let data = sequence.data(using: .utf8)
        else {
            fputs("veil: failed to encode workspace user var\n", stderr)
            return false
        }
        FileHandle.standardOutput.write(data)
        return true
    }

    static func printWorkspaces() -> Bool {
        let table = loadRegistry()
        let host = listenHost()
        for (root, entry) in table.sorted(by: { $0.key < $1.key }) {
            let status = serverState(of: entry, addr: "\(host):\(entry.port)").rawValue
            let name = URL(fileURLWithPath: root).lastPathComponent
            print(
                status.padded(to: 6) + name.padded(to: 24) + "\(entry.port)".padded(to: 6) + root)
        }
        return true
    }

    // MARK: - Workspace identity

    /// Project root = git root; anything outside a repository shares one
    /// default workspace rooted at $HOME instead of spawning a server per
    /// random directory.
    private static func resolveWorkspaceRoot() -> (root: String, name: String) {
        if let result = runCapture(
            "/usr/bin/env", ["git", "rev-parse", "--show-toplevel"], timeout: 3),
            result.status == 0,
            let output = String(data: result.stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty
        {
            return (output, URL(fileURLWithPath: output).lastPathComponent)
        }
        return (FileManager.default.homeDirectoryForCurrentUser.path, "home")
    }

    /// Address other machines reach this host by: explicit override, else
    /// the Tailscale MagicDNS self name, else the plain hostname.
    private static func listenHost() -> String {
        if let override = ProcessInfo.processInfo.environment["VEIL_WORKSPACE_HOST"],
            !override.isEmpty
        {
            return override
        }
        if let result = runCapture("/usr/bin/env", ["tailscale", "status", "--json"], timeout: 3),
            result.status == 0,
            let object = try? JSONSerialization.jsonObject(with: result.stdout)
                as? [String: Any],
            let selfNode = object["Self"] as? [String: Any],
            let dnsName = selfNode["DNSName"] as? String,
            !dnsName.isEmpty
        {
            return dnsName.hasSuffix(".") ? String(dnsName.dropLast()) : dnsName
        }
        return WorkspaceViewer.normalize(hostname: ProcessInfo.processInfo.hostName)
    }

    // MARK: - Server lifecycle

    private static func probe(_ addr: String) -> Bool {
        runCapture("/usr/bin/env", ["nvim", "--server", addr, "--remote-expr", "1"], timeout: 3)?
            .status == 0
    }

    /// Classifies a registry entry by its pid's command line as well as
    /// the socket, so a server that is merely blocked is never mistaken for
    /// a dead one (see `WorkspaceRegistry.serverState`).
    private static func serverState(
        of entry: WorkspaceRegistry.Entry, addr: String
    ) -> WorkspaceRegistry.ServerState {
        WorkspaceRegistry.serverState(
            answersProbe: probe(addr), commandLine: commandLine(ofPid: entry.pid), addr: addr)
    }

    /// nil when no such process exists. A non-positive pid is never looked
    /// up: `ps -p 0` would describe the kernel, not a workspace server.
    private static func commandLine(ofPid pid: Int32) -> String? {
        guard pid > 0,
            let result = runCapture("/bin/ps", ["-p", "\(pid)", "-o", "command="], timeout: 3),
            result.status == 0
        else { return nil }
        return String(data: result.stdout, encoding: .utf8)
    }

    /// A busy server may hold unsaved buffers, so it is neither signaled
    /// nor replaced; the user retries once the blocking command finishes.
    private static func reportBusy(name: String, entry: WorkspaceRegistry.Entry, addr: String) {
        fputs(
            "veil: workspace '\(name)' is busy: its nvim (pid \(entry.pid), \(addr)) is running "
                + "but not answering, probably blocked on a long command. "
                + "Left it untouched; try again once it finishes.\n", stderr)
    }

    private static let portRange = 6700...6899

    private static func pickPort(host: String, table: WorkspaceRegistry.Table) -> Int? {
        let registered = Set(table.values.map(\.port))
        for _ in 0..<20 {
            let port = Int.random(in: portRange)
            if registered.contains(port) { continue }
            if probe("\(host):\(port)") { continue }
            return port
        }
        return nil
    }

    /// Spawns the headless server fully detached from this terminal
    /// session: nohup makes it immune to SIGHUP, stdio is redirected, and
    /// once the CLI exits the server is an orphan outside the shell's job
    /// table, so closing the pane cannot reach it.
    private static func spawnServer(root: String, name: String, addr: String) -> Int32? {
        let log = logsDir.appendingPathComponent("\(name).log")
        guard let logHandle = appendHandle(for: log) else {
            fputs("veil: cannot open log file \(log.path)\n", stderr)
            return nil
        }
        defer { try? logHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["nohup", "nvim", "--headless", "--listen", addr]
        process.currentDirectoryURL = URL(fileURLWithPath: root)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = logHandle
        process.standardError = logHandle
        do {
            try process.run()
        } catch {
            fputs("veil: failed to spawn workspace server: \(error.localizedDescription)\n", stderr)
            return nil
        }

        for _ in 0..<50 {
            if probe(addr) { return process.processIdentifier }
            Thread.sleep(forTimeInterval: 0.2)
        }
        fputs(
            "veil: server for '\(name)' did not become ready on \(addr) (see \(log.path))\n", stderr
        )
        return nil
    }

    private static func sendFiles(_ nvimArgs: [String], to addr: String) -> Bool {
        guard !nvimArgs.isEmpty else { return true }
        let cwd = FileManager.default.currentDirectoryPath
        // Absolutize bare paths; leave nvim's own `-`/`+` arguments alone.
        let arguments = nvimArgs.map { arg in
            arg.hasPrefix("/") || arg.hasPrefix("-") || arg.hasPrefix("+")
                ? arg : cwd + "/" + arg
        }
        guard
            let result = runCapture(
                "/usr/bin/env", ["nvim", "--server", addr, "--remote"] + arguments, timeout: 10),
            result.status == 0
        else {
            fputs("veil: failed to send files to workspace server at \(addr)\n", stderr)
            return false
        }
        return true
    }

    // MARK: - Registry persistence

    private static var stateDir: URL {
        let base =
            ProcessInfo.processInfo.environment["XDG_STATE_HOME"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state")
        return base.appendingPathComponent("veil")
    }

    private static var registryURL: URL { stateDir.appendingPathComponent("registry.json") }
    private static var logsDir: URL { stateDir.appendingPathComponent("logs") }

    private static func loadRegistry() -> WorkspaceRegistry.Table {
        guard let data = try? Data(contentsOf: registryURL) else { return [:] }
        return WorkspaceRegistry.decode(data)
    }

    /// Atomic replace (temp file + rename) so a concurrent invocation
    /// never observes a half-written registry. Failure to persist is not
    /// fatal: the server is already running and reachable, the entry is
    /// merely forgotten.
    private static func saveRegistry(_ table: WorkspaceRegistry.Table) {
        do {
            try FileManager.default.createDirectory(
                at: stateDir, withIntermediateDirectories: true)
            let data = try WorkspaceRegistry.encode(table)
            let tmp = stateDir.appendingPathComponent("registry.json.\(UUID().uuidString)")
            try data.write(to: tmp)
            _ = try FileManager.default.replaceItemAt(registryURL, withItemAt: tmp)
        } catch {
            fputs(
                "veil: failed to write workspace registry: \(error.localizedDescription)\n", stderr)
        }
    }

    private static func appendHandle(for log: URL) -> FileHandle? {
        do {
            try FileManager.default.createDirectory(
                at: logsDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: log.path) else { return nil }
        _ = try? handle.seekToEnd()
        return handle
    }

    // MARK: - Subprocess plumbing

    /// Runs a subprocess, captures stdout, and enforces a wall-clock
    /// timeout by SIGKILLing the pid from a detached work item. Returns
    /// nil when the process cannot be started at all.
    private static func runCapture(
        _ executable: String, _ arguments: [String], timeout: TimeInterval
    ) -> (status: Int32, stdout: Data)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        let pid = process.processIdentifier
        let watchdog = DispatchWorkItem { kill(pid, SIGKILL) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let stdout = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, stdout)
    }
}

extension String {
    fileprivate func padded(to width: Int) -> String {
        count >= width ? self + " " : padding(toLength: width, withPad: " ", startingAt: 0)
    }
}
