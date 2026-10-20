import Foundation
import VeilCore

/// Server-side half of the remote workspace flow. When the human behind
/// this command sits on another machine (per wezterm's client metadata),
/// the CLI does not open a local window: it keeps one headless
/// `nvim --headless --listen` per project root (tracked in the registry),
/// sends the requested files and the nvim arguments that still apply to a
/// running nvim into it, and broadcasts a user var telling
/// the viewer's machine to attach a Veil window via `veil --veil-connect`.
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
        let result = runCapture("/usr/bin/env", WorkspaceViewer.listClientsArguments, timeout: 2)
        return WorkspaceViewer.remoteViewer(
            ofFreshestClientIn: result?.status == 0 ? result?.stdout : nil,
            localHostname: WorkspaceViewer.localHostname())
    }

    // MARK: - Main flows

    static func summon(nvimArgs: [String], viewer: String) -> Bool {
        // Translate before touching any server: a refused argument must not
        // leave a freshly spawned workspace behind.
        let openExpression: String?
        do {
            openExpression = try WorkspaceNvimArguments.remoteExpression(
                for: nvimArgs, cwd: FileManager.default.currentDirectoryPath)
        } catch {
            fputs("veil: \(error.message)\n", stderr)
            return false
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let root = resolveWorkspaceRoot(home: home)
        let name = WorkspaceRoot.name(of: root, home: home)
        guard let host = listenHost(),
            let server = prepareServer(root: root, name: name, host: host)
        else { return false }

        guard applyArguments(openExpression, on: server.address(currentHost: host)) else {
            return false
        }
        let payload = WorkspaceUserVar.payload(
            for: server, currentHost: host, workspace: name, viewer: viewer)
        guard let sequence = WorkspaceUserVar.sequence(for: payload),
            let data = sequence.data(using: .utf8)
        else {
            fputs("veil: failed to encode workspace user var\n", stderr)
            return false
        }
        guard
            let terminal = WorkspaceUserVar.terminal(
                stdoutIsTerminal: isatty(STDOUT_FILENO) == 1,
                openControllingTerminal: { FileHandle(forWritingAtPath: "/dev/tty") })
        else {
            fputs(
                "veil: workspace '\(name)' is ready, but no window can be "
                    + "requested: stdout is not a terminal and there is no controlling "
                    + "terminal to tell wezterm through\n", stderr)
            return false
        }
        terminal.write(data)
        return true
    }

    static func printWorkspaces() -> Bool {
        let table = registryFile.load()
        // Listing needs a current host only for entries that never recorded
        // theirs, so its absence is reported, not fatal.
        let host = resolveListenHost()
        if host == nil {
            fputs(
                "veil: no address to serve workspaces on right now (Tailscale is unavailable "
                    + "and workspace_host is not set), so workspaces registered without a "
                    + "host whose server is not running show as unknown; set workspace_host in "
                    + "\(configPath.path) to probe them\n", stderr)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for (root, recorded) in table.sorted(by: { $0.key < $1.key }) {
            let entry = withListenHost(recorded)
            let status = WorkspaceRegistry.listedStatus(of: entry, currentHost: host) {
                serverState(of: entry, addr: $0)
            }
            let name = WorkspaceRoot.name(of: root, home: home)
            let listedHost = WorkspaceRegistry.listedHost(of: entry, currentHost: host)
            print(
                status.padded(to: 12) + name.padded(to: 24) + listedHost.padded(to: 18)
                    + "\(entry.port)".padded(to: 6) + root)
        }
        return true
    }

    // MARK: - Workspace identity

    /// Project root = git root; anything outside a repository shares one
    /// default workspace rooted at $HOME instead of spawning a server per
    /// random directory.
    private static func resolveWorkspaceRoot(home: String) -> String {
        if let result = runCapture(
            "/usr/bin/env", ["git", "rev-parse", "--show-toplevel"], timeout: 3),
            result.status == 0,
            let output = String(data: result.stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty
        {
            return output
        }
        return home
    }

    /// Address other machines reach this host by (see
    /// `WorkspaceListenHost.resolve`). Reports on stderr when there is none.
    private static func listenHost() -> String? {
        let host = resolveListenHost()
        if host == nil {
            fputs(
                "veil: no address to serve the workspace on: Tailscale is unavailable and "
                    + "workspace_host is not set; set it in \(configPath.path)\n", stderr)
        }
        return host
    }

    private static var configPath: URL {
        VeilConfigFile.path(
            environment: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// `listenHost` without the report, for callers that can go on without one.
    private static func resolveListenHost() -> String? {
        WorkspaceListenHost.resolve(
            configured: configuredWorkspaceHost(in: configPath),
            tailscaleStatus: {
                let result = runCapture(
                    "/usr/bin/env", ["tailscale", "status", "--json"], timeout: 3)
                return result?.status == 0 ? result?.stdout : nil
            })
    }

    /// A config file that cannot be read, or a `workspace_host` that names
    /// no single address (see `WorkspaceListenHost.problem`), is reported
    /// and treated as not setting it, as the app falls back to its
    /// defaults then.
    private static func configuredWorkspaceHost(in configPath: URL) -> String? {
        do {
            guard let host = try VeilConfigFile.workspaceHost(inFileAt: configPath) else {
                return nil
            }
            if let problem = WorkspaceListenHost.problem(withConfiguredHost: host) {
                fputs(
                    "veil: ignoring workspace_host '\(host)' in \(configPath.path): \(problem)\n",
                    stderr)
                return nil
            }
            return host
        } catch {
            fputs(
                "veil: ignoring workspace_host: cannot read \(configPath.path): "
                    + "\(error.message)\n", stderr)
            return nil
        }
    }

    // MARK: - Server lifecycle

    /// The server for `root`: the registered one when it answers, else a
    /// freshly spawned and registered one. nil, reported on stderr, when
    /// the registered one is busy or unreachable, or no new one could be
    /// started. The registry stays locked throughout, so a concurrent run
    /// for the same root waits, then finds this server instead of spawning
    /// another.
    private static func prepareServer(
        root: String, name: String, host: String
    ) -> WorkspaceRegistry.Entry? {
        let lock = lockRegistry()
        defer { lock?.unlock() }
        var table = registryFile.load()

        // Each server is looked for where it was started, which need not be
        // where this run would start one.
        if let recorded = table[root] {
            let entry = withListenHost(recorded)
            if entry != recorded {
                table[root] = entry
                saveRegistry(table)
            }
            let addr = entry.address(currentHost: host)
            let state = serverState(of: entry, addr: addr)
            switch WorkspaceRegistry.decision(for: state) {
            case .reuse:
                return entry
            case .leaveAlone:
                let refusal = WorkspaceRegistry.refusal(
                    for: state, workspace: name, entry: entry, addr: addr)
                fputs("veil: \(refusal ?? "workspace '\(name)' was left untouched")\n", stderr)
                return nil
            case .forgetAndSpawn, .spawn:
                // Gone, or its pid now runs something else: forget the entry
                // without signaling anything, and on disk at once, so a spawn
                // that fails below does not leave the stale entry behind.
                table[root] = nil
                saveRegistry(table)
            }
        }
        guard let picked = pickPort(host: host, table: table) else {
            fputs("veil: no free workspace port in \(portRange)\n", stderr)
            return nil
        }
        guard let spawned = spawnServer(root: root, name: name, addr: "\(host):\(picked)") else {
            return nil
        }
        let server = WorkspaceRegistry.Entry(host: host, port: picked, pid: spawned.pid)
        table[root] = server
        saveRegistry(table)
        spawned.interruptGuard.disarm()
        return server
    }

    /// `entry` with the host its server listens on filled in from the
    /// server's command line, for an entry that never recorded one (see
    /// `WorkspaceRegistry.Entry.adoptingListenHost`).
    private static func withListenHost(_ entry: WorkspaceRegistry.Entry) -> WorkspaceRegistry.Entry
    {
        guard entry.host == nil else { return entry }
        return entry.adoptingListenHost(fromCommandLine: commandLine(ofPid: entry.pid))
    }

    private static func probe(_ addr: String) -> WorkspaceRegistry.ProbeResult {
        let result = runCapture(
            "/usr/bin/env", ["nvim", "--server", addr, "--remote-expr", "1"], timeout: 3)
        return .init(exitStatus: result?.status, timedOut: result?.timedOut ?? false)
    }

    /// Classifies a registry entry by its pid's command line as well as
    /// the socket, so a server that is merely blocked is never mistaken for
    /// a dead one (see `WorkspaceRegistry.serverState`).
    private static func serverState(
        of entry: WorkspaceRegistry.Entry, addr: String
    ) -> WorkspaceRegistry.ServerState {
        let result = WorkspaceRegistry.ProbeResult(
            addr: addr, isOnThisMachine: LocalAddresses.isOnThisMachine,
            rpcProbe: { probe(addr) })
        return WorkspaceRegistry.serverState(
            probe: result, commandLine: commandLine(ofPid: entry.pid), addr: addr)
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

    private static let portRange = 6700...6899

    private static func pickPort(host: String, table: WorkspaceRegistry.Table) -> Int? {
        let registered = Set(table.values.map(\.port))
        for _ in 0..<20 {
            let port = Int.random(in: portRange)
            if registered.contains(port) { continue }
            if probe("\(host):\(port)") == .answered { continue }
            return port
        }
        return nil
    }

    /// Spawns the headless server fully detached from this terminal
    /// session: nohup makes it immune to SIGHUP, stdio is redirected, and
    /// once the CLI exits the server is an orphan outside the shell's job
    /// table, so closing the pane cannot reach it.
    /// The server's pid, and the guard that ends it if `veil` is
    /// interrupted before it is registered; the caller disarms the guard
    /// once the registry records the server.
    private static func spawnServer(
        root: String, name: String, addr: String
    ) -> (pid: Int32, interruptGuard: WorkspaceServerStartup.InterruptGuard)? {
        let log = logsDir.appendingPathComponent(WorkspaceRoot.logFileName(of: root))
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

        let interruptGuard = WorkspaceServerStartup.InterruptGuard(ending: process) { signal in
            fputs("veil: interrupted; stopped the workspace server that was starting\n", stderr)
            exit(128 + signal)
        }
        let ready = WorkspaceServerStartup.awaitReady(
            process, timeout: 10, interval: 0.2, answers: { probe(addr) == .answered })
        guard ready else {
            interruptGuard.disarm()
            fputs(
                "veil: server for '\(name)' did not become ready on \(addr) "
                    + "and was stopped (see \(log.path))\n", stderr)
            return nil
        }
        return (process.processIdentifier, interruptGuard)
    }

    /// Evaluates the translated arguments (see `WorkspaceNvimArguments`)
    /// on the server. `--remote-expr`, unlike `--remote`, fails at once
    /// when the server is unreachable instead of editing locally. Only a
    /// failure to open the files is fatal; a `+cmd` that fails afterwards
    /// is reported and the window still opens, as a local nvim would. So
    /// does a file left with a swap file, opened read-only with a note.
    private static func applyArguments(_ openExpression: String?, on addr: String) -> Bool {
        guard let openExpression else { return true }
        let result = runCapture(
            "/usr/bin/env", ["nvim", "--server", addr, "--remote-expr", openExpression],
            timeout: 10)
        guard let result, result.status == 0 else {
            fputs("veil: failed to open files in workspace server at \(addr)\n", stderr)
            // nvim's own words are the only record of why; pass them on as is.
            // Terminate the line when nvim did not, so the shell prompt
            // never joins it.
            if let result, !result.stderr.isEmpty {
                FileHandle.standardError.write(result.stderr)
                if result.stderr.last != UInt8(ascii: "\n") {
                    FileHandle.standardError.write(Data("\n".utf8))
                }
            }
            return false
        }
        let reply = String(decoding: result.stdout, as: UTF8.self)
        for failure in WorkspaceNvimArguments.commandFailures(inReply: reply) {
            fputs("veil: \(failure)\n", stderr)
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

    private static var registryFile: WorkspaceRegistryFile { .init(directory: stateDir) }
    private static var logsDir: URL { stateDir.appendingPathComponent("logs") }

    /// Failing to lock is not fatal, any more than failing to save: the
    /// run goes ahead as it did before the registry had a lock.
    private static func lockRegistry() -> WorkspaceRegistryFile.Lock? {
        do {
            return try registryFile.lock()
        } catch {
            fputs(
                "veil: proceeding without locking the workspace registry: "
                    + "\(error.localizedDescription)\n", stderr)
            return nil
        }
    }

    /// Failure to persist is not fatal: the server is already running and
    /// reachable, the entry is merely forgotten.
    private static func saveRegistry(_ table: WorkspaceRegistry.Table) {
        do {
            try registryFile.save(table)
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

    /// Runs a subprocess, captures stdout and stderr, and enforces a
    /// wall-clock timeout by SIGKILLing the pid from a detached work item;
    /// `timedOut` tells that kill apart from an ordinary exit. Returns nil
    /// when the process cannot be started at all.
    private static func runCapture(
        _ executable: String, _ arguments: [String], timeout: TimeInterval
    ) -> (status: Int32, stdout: Data, stderr: Data, timedOut: Bool)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        let pid = process.processIdentifier
        let watchdog = DispatchWorkItem { kill(pid, SIGKILL) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // Drain stderr concurrently: reading the two pipes one after the
        // other deadlocks once the child fills the unread one.
        let errorOutput = DrainedOutput()
        let stderrDrained = DispatchGroup()
        DispatchQueue.global().async(group: stderrDrained) {
            errorOutput.data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        stderrDrained.wait()
        process.waitUntilExit()
        watchdog.cancel()
        let timedOut =
            process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL
        return (process.terminationStatus, output, errorOutput.data, timedOut)
    }
}

/// Holds what a background reader drained from a pipe. Written once by
/// that reader and read only after `DispatchGroup.wait()` returns, which
/// orders the two accesses, so no lock is needed.
private final class DrainedOutput: @unchecked Sendable {
    var data = Data()
}

extension String {
    fileprivate func padded(to width: Int) -> String {
        count >= width ? self + " " : padding(toLength: width, withPad: " ", startingAt: 0)
    }
}
