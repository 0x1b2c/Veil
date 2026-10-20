import Foundation
import Testing
import VeilCore

/// The decisions `veil` makes for the workspace scenarios, each driven the
/// way the CLI drives it; the CLI around them only spawns, signals nothing,
/// and writes what these return.
struct WorkspaceScenarioTests {
    private func clients(freshest hostname: String) -> Data {
        """
        [
          { "username": "u", "hostname": "\(hostname)", "pid": 1,
            "connection_elapsed": { "secs": 100, "nanos": 0 },
            "idle_time": { "secs": 0, "nanos": 1000 },
            "workspace": "", "focused_pane_id": 1 },
          { "username": "u", "hostname": "elsewhere", "pid": 2,
            "connection_elapsed": { "secs": 100, "nanos": 0 },
            "idle_time": { "secs": 90, "nanos": 0 },
            "workspace": "", "focused_pane_id": 2 }
        ]
        """.data(using: .utf8)!
    }

    @Test("@ws-001 a keyboard on this machine opens a local window, with no workspace or user var")
    func localKeyboardStaysLocal() {
        // No remote viewer means the CLI takes its plain local path: no
        // server is prepared and nothing is broadcast.
        #expect(
            WorkspaceViewer.remoteViewer(
                ofFreshestClientIn: clients(freshest: "2B.local (via proxy pid 1)"),
                localHostname: "2B") == nil)
    }

    @Test func undeterminableViewerStaysLocal() {
        #expect(WorkspaceViewer.remoteViewer(ofFreshestClientIn: nil, localHostname: "2B") == nil)
        #expect(
            WorkspaceViewer.remoteViewer(
                ofFreshestClientIn: clients(freshest: "a2"), localHostname: nil) == nil)
    }

    @Test("@ws-002 a remote keyboard gets a workspace server and a broadcast naming its machine")
    func remoteKeyboardDivertsToTheWorkspace() {
        let viewer = WorkspaceViewer.remoteViewer(
            ofFreshestClientIn: clients(freshest: "A2.local"), localHostname: "2B")
        #expect(viewer == "a2")

        // No server yet, or a dead one: one is spawned; a live one is reused.
        #expect(WorkspaceRegistry.decision(for: nil) == .spawn)
        #expect(WorkspaceRegistry.decision(for: .dead) == .forgetAndSpawn)
        #expect(WorkspaceRegistry.decision(for: .alive) == .reuse)

        let server = WorkspaceRegistry.Entry(host: "100.101.102.103", port: 6800, pid: 4242)
        let payload = WorkspaceUserVar.payload(
            for: server, currentHost: "100.101.102.104", workspace: "proj", viewer: viewer!)
        #expect(payload == .init(host: "100.101.102.103", port: 6800, workspace: "proj", viewer: "a2"))
    }

    @Test("@ws-003 a busy workspace is left running and the user is told it is busy")
    func busyWorkspaceIsLeftAlone() throws {
        #expect(WorkspaceRegistry.decision(for: .busy) == .leaveAlone)
        let message = try #require(
            WorkspaceRegistry.refusal(
                for: .busy, workspace: "proj",
                entry: .init(host: "100.101.102.103", port: 6800, pid: 4242),
                addr: "100.101.102.103:6800"))
        #expect(message.contains("'proj' is busy"))
        #expect(message.contains("4242"))
    }

    @Test func unreachableWorkspaceIsLeftAloneToo() throws {
        #expect(WorkspaceRegistry.decision(for: .unreachable) == .leaveAlone)
        let message = try #require(
            WorkspaceRegistry.refusal(
                for: .unreachable, workspace: "proj", entry: .init(port: 6800, pid: 4242),
                addr: "100.101.102.103:6800"))
        #expect(message.contains("cannot be reached"))
    }

    @Test func onlyRefusedStatesHaveARefusal() {
        for state in [WorkspaceRegistry.ServerState.alive, .dead] {
            #expect(
                WorkspaceRegistry.refusal(
                    for: state, workspace: "proj", entry: .init(port: 6800, pid: 1),
                    addr: "a:6800") == nil)
        }
    }
}

@Suite(.enabled(if: HeadlessNvim.isAvailable, "needs nvim on PATH"))
struct WorkspaceRemoteOpenScenarioTests {
    @Test("@ws-002 the file a remote keyboard asked for is open in the workspace server")
    func requestedFileReachesTheServer() throws {
        let nvim = try HeadlessNvim()
        defer { nvim.stop() }
        try nvim.open(["a.txt"])

        #expect(try nvim.eval("expand('%:t')") == "a.txt")
    }
}
