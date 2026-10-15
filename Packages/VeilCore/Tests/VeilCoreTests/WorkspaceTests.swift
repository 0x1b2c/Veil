import Foundation
import Testing
import VeilCore

struct WorkspaceViewerTests {
    /// Shape captured from a real `wezterm cli list-clients --format json`
    /// run: one local client, one attached over SSH with a decorated
    /// hostname, extra fields the decoder must tolerate.
    private func clientsJSON(localIdleSecs: UInt64, remoteIdleSecs: UInt64) -> Data {
        """
        [
          {
            "username": "someone",
            "hostname": "2B",
            "pid": 2229,
            "connection_elapsed": { "secs": 106412, "nanos": 308494000 },
            "idle_time": { "secs": \(localIdleSecs), "nanos": 308494000 },
            "workspace": "",
            "focused_pane_id": 44,
            "ssh_auth_sock": "/var/run/x/Listeners"
          },
          {
            "username": "someone",
            "hostname": "A2.local (via proxy pid 13754)",
            "pid": 30902,
            "connection_elapsed": { "secs": 5257, "nanos": 308513000 },
            "idle_time": { "secs": \(remoteIdleSecs), "nanos": 308513000 },
            "workspace": "",
            "focused_pane_id": 44,
            "ssh_auth_sock": null
          }
        ]
        """.data(using: .utf8)!
    }

    @Test func remoteClientFreshest() {
        let location = WorkspaceViewer.location(
            ofFreshestClientIn: clientsJSON(localIdleSecs: 2055, remoteIdleSecs: 1),
            localHostname: "2B.local")
        #expect(location == .remote(host: "a2"))
    }

    @Test func staleRemoteWinnerIsUndecidable() {
        // Nobody typed this recently (a delayed script, not a keystroke):
        // a remote winner past the trust threshold must not divert.
        let location = WorkspaceViewer.location(
            ofFreshestClientIn: clientsJSON(localIdleSecs: 2055, remoteIdleSecs: 10),
            localHostname: "2B.local")
        #expect(location == nil)
    }

    @Test func localClientFreshest() {
        let location = WorkspaceViewer.location(
            ofFreshestClientIn: clientsJSON(localIdleSecs: 0, remoteIdleSecs: 3600),
            localHostname: "2B.local")
        #expect(location == .local)
    }

    @Test func staleLocalWinnerStaysLocal() {
        // The threshold guards only remote diversion; a stale local winner
        // and the fallback mean the same thing, so decide .local outright.
        let location = WorkspaceViewer.location(
            ofFreshestClientIn: clientsJSON(localIdleSecs: 3600, remoteIdleSecs: 7200),
            localHostname: "2B.local")
        #expect(location == .local)
    }

    @Test func nanosBreakSecondsTie() {
        // Equal secs: the local client's smaller nanos wins.
        let location = WorkspaceViewer.location(
            ofFreshestClientIn: clientsJSON(localIdleSecs: 5, remoteIdleSecs: 5),
            localHostname: "2b")
        #expect(location == .local)
    }

    @Test func emptyClientListIsUndecidable() {
        let location = WorkspaceViewer.location(
            ofFreshestClientIn: "[]".data(using: .utf8)!, localHostname: "2b")
        #expect(location == nil)
    }

    @Test func garbageIsUndecidable() {
        let location = WorkspaceViewer.location(
            ofFreshestClientIn: "not json".data(using: .utf8)!, localHostname: "2b")
        #expect(location == nil)
    }

    @Test("@ws-001 this machine's name comes from the source wezterm reads")
    func localHostnameSharesItsSourceWithOtherTools() throws {
        // Scenario: editing while sitting at this machine opens a local
        // window. That only holds if our idea of "this machine" is the very
        // name wezterm reports for its local client, which it reads from
        // gethostname(). Pin the source by comparing against `hostname`,
        // which reads the same place; a Mac whose computer name was
        // customized reports something else entirely elsewhere.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/hostname")
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let expected = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!expected.isEmpty)
        #expect(WorkspaceViewer.localHostname() == expected)
    }

    @Test func normalizeComparesFirstLabelOnly() {
        #expect(WorkspaceViewer.normalize(hostname: "A2.local (via proxy pid 13754)") == "a2")
        #expect(WorkspaceViewer.normalize(hostname: "2B") == "2b")
        #expect(WorkspaceViewer.normalize(hostname: "2B.local") == "2b")
        #expect(WorkspaceViewer.normalize(hostname: "Foo.Local") == "foo")
        #expect(WorkspaceViewer.normalize(hostname: "a2 (proxy)") == "a2")
        #expect(WorkspaceViewer.normalize(hostname: "2b.tail1234.ts.net") == "2b")
    }

    @Test func fqdnAndLocalSuffixNameTheSameMachine() {
        // The same host may call itself "2B.local" (macOS) or a Tailscale
        // FQDN; both must compare equal to each other and unequal to a2.
        let fqdn = WorkspaceViewer.normalize(hostname: "2b.tail1234.ts.net")
        #expect(fqdn == WorkspaceViewer.normalize(hostname: "2B.local"))
        #expect(fqdn != WorkspaceViewer.normalize(hostname: "A2.local (via proxy pid 13754)"))
    }
}

struct WorkspaceRegistryTests {
    @Test func roundTrip() throws {
        let table: WorkspaceRegistry.Table = [
            "/Users/x/proj": .init(port: 6800, pid: 4242),
            "/Users/x": .init(port: 6701, pid: 99),
        ]
        let decoded = WorkspaceRegistry.decode(try WorkspaceRegistry.encode(table))
        #expect(decoded == table)
    }

    @Test func registryWrittenBeforeHostsWereRecordedKeepsItsEntries() {
        // decode() turns any failure into an empty table, so a field these
        // entries lack would orphan every server they track.
        let legacy = Data(
            #"{ "/Users/x/proj": { "pid": 4242, "port": 6800 }, "/Users/x": { "pid": 99, "port": 6701 } }"#
                .utf8)
        let table = WorkspaceRegistry.decode(legacy)
        #expect(table["/Users/x/proj"] == .init(port: 6800, pid: 4242))
        #expect(table["/Users/x"] == .init(port: 6701, pid: 99))
    }

    @Test func recordedHostSurvivesRoundTrip() {
        let table: WorkspaceRegistry.Table = [
            "/Users/x/proj": .init(host: "2b.tail1234.ts.net", port: 6800, pid: 4242)
        ]
        let decoded = WorkspaceRegistry.decode(try! WorkspaceRegistry.encode(table))
        #expect(decoded["/Users/x/proj"]?.host == "2b.tail1234.ts.net")
    }

    @Test func serverIsAddressedWhereItWasStartedEvenAfterTheHostChanged() {
        // Tailscale went away after the server was spawned: probing the
        // current fallback name would miss it and spawn a duplicate.
        let entry = WorkspaceRegistry.Entry(
            host: "2b.tail1234.ts.net", port: 6800, pid: 4242)
        #expect(
            entry.address(currentHost: "Example-Mac.local") == "2b.tail1234.ts.net:6800")
    }

    @Test func entryWithoutRecordedHostIsAddressedAtTheCurrentHost() {
        let entry = WorkspaceRegistry.Entry(port: 6800, pid: 4242)
        #expect(entry.address(currentHost: "127.0.0.1") == "127.0.0.1:6800")
    }

    @Test func corruptDataHealsToEmpty() {
        #expect(WorkspaceRegistry.decode("{oops".data(using: .utf8)!).isEmpty)
        #expect(WorkspaceRegistry.decode(Data()).isEmpty)
    }
}

struct WorkspaceServerStateTests {
    private let addr = "127.0.0.1:6991"

    /// `ps -p <pid> -o command=` as captured for a server spawned through
    /// `env nohup nvim --headless --listen`: argv[0] is the full path.
    private var serverCommand: String { "/opt/homebrew/bin/nvim --headless --listen \(addr)\n" }

    @Test("@ws-003 a running server that does not answer is busy, not dead")
    func busyServerIsNotDead() {
        let state = WorkspaceRegistry.serverState(
            probe: .timedOut, commandLine: serverCommand, addr: addr)
        #expect(state == .busy)
    }

    @Test func runningServerWhoseAddressFailsAtOnceIsUnreachable() {
        // The address it was started on no longer resolves or refuses the
        // connection (say, its Tailscale name is gone): nothing suggests a
        // blocked nvim, so it must not be reported as busy.
        let state = WorkspaceRegistry.serverState(
            probe: .failed, commandLine: serverCommand, addr: addr)
        #expect(state == .unreachable)
    }

    @Test func answeringServerIsAlive() {
        let state = WorkspaceRegistry.serverState(
            probe: .answered, commandLine: serverCommand, addr: addr)
        #expect(state == .alive)
    }

    @Test func missingProcessIsDead() {
        for probe in [WorkspaceRegistry.ProbeResult.timedOut, .failed] {
            let state = WorkspaceRegistry.serverState(probe: probe, commandLine: nil, addr: addr)
            #expect(state == .dead)
        }
    }

    @Test func reusedPidIsDead() {
        for probe in [WorkspaceRegistry.ProbeResult.timedOut, .failed] {
            let state = WorkspaceRegistry.serverState(
                probe: probe, commandLine: "/usr/bin/ssh-agent -l\n", addr: addr)
            #expect(state == .dead)
        }
    }

    @Test func serverOnAnotherAddressIsDead() {
        // A port that merely shares a prefix with ours is a different server.
        let state = WorkspaceRegistry.serverState(
            probe: .failed,
            commandLine: "/opt/homebrew/bin/nvim --headless --listen 127.0.0.1:69910\n",
            addr: addr)
        #expect(state == .dead)
    }

    @Test func otherProgramListeningOnOurAddressIsDead() {
        let state = WorkspaceRegistry.serverState(
            probe: .timedOut, commandLine: "/usr/bin/nc --listen \(addr)", addr: addr)
        #expect(state == .dead)
    }
}

struct WorkspaceProbeResultTests {
    @Test func zeroStatusIsAnAnswer() {
        #expect(WorkspaceRegistry.ProbeResult(exitStatus: 0, timedOut: false) == .answered)
    }

    @Test func probeKilledAtTheTimeoutTimedOut() {
        // A blocked nvim accepts the connection and never replies, so the
        // probe waits until the timeout kills it.
        #expect(WorkspaceRegistry.ProbeResult(exitStatus: SIGKILL, timedOut: true) == .timedOut)
    }

    @Test func probeThatExitsWithAnErrorFailed() {
        // `nvim --server` exits 2 within a fraction of a second when the
        // host does not resolve or the connection is refused.
        #expect(WorkspaceRegistry.ProbeResult(exitStatus: 2, timedOut: false) == .failed)
    }

    @Test func probeThatCouldNotRunFailed() {
        #expect(WorkspaceRegistry.ProbeResult(exitStatus: nil, timedOut: false) == .failed)
    }
}

struct WorkspaceUserVarTests {
    @Test func sequenceCarriesDecodablePayload() throws {
        let payload = WorkspaceUserVar.Payload(
            host: "2b.tail1234.ts.net", port: 6800, workspace: "proj", viewer: "a2")
        let sequence = try #require(WorkspaceUserVar.sequence(for: payload))
        let prefix = "\u{1B}]1337;SetUserVar=veil-edit="
        #expect(sequence.hasPrefix(prefix))
        #expect(sequence.hasSuffix("\u{07}"))
        let base64 = String(sequence.dropFirst(prefix.count).dropLast(1))
        let json = try #require(Data(base64Encoded: base64))
        let decoded = try JSONDecoder().decode(WorkspaceUserVar.Payload.self, from: json)
        #expect(decoded == payload)
    }

    @Test func sequenceGoesToStdoutWhenItIsTheTerminal() {
        var opened = false
        let terminal = WorkspaceUserVar.terminal(
            stdoutIsTerminal: true,
            openControllingTerminal: {
                opened = true
                return nil
            })
        #expect(terminal === FileHandle.standardOutput)
        #expect(!opened)
    }

    @Test func redirectedStdoutSendsTheSequenceToTheControllingTerminal() {
        // `veil foo.txt | cat` or `$(veil foo.txt)`: wezterm only parses
        // what reaches the pane's terminal.
        let tty = FileHandle.nullDevice
        let terminal = WorkspaceUserVar.terminal(
            stdoutIsTerminal: false, openControllingTerminal: { tty })
        #expect(terminal === tty)
    }

    @Test func withoutAnyTerminalThereIsNowhereToSendTheSequence() {
        let terminal = WorkspaceUserVar.terminal(
            stdoutIsTerminal: false, openControllingTerminal: { nil })
        #expect(terminal == nil)
    }
}
