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
            ofFreshestClientIn: clientsJSON(localIdleSecs: 2055, remoteIdleSecs: 10),
            localHostname: "2B.local")
        #expect(location == .remote(host: "a2"))
    }

    @Test func localClientFreshest() {
        let location = WorkspaceViewer.location(
            ofFreshestClientIn: clientsJSON(localIdleSecs: 0, remoteIdleSecs: 3600),
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

    @Test func normalizeStripsDecorationAndLocalSuffix() {
        #expect(WorkspaceViewer.normalize(hostname: "A2.local (via proxy pid 13754)") == "a2")
        #expect(WorkspaceViewer.normalize(hostname: "2B") == "2b")
        #expect(WorkspaceViewer.normalize(hostname: "2B.local") == "2b")
        #expect(WorkspaceViewer.normalize(hostname: "Foo.Local") == "foo")
        #expect(WorkspaceViewer.normalize(hostname: "a2 (proxy)") == "a2")
        #expect(
            WorkspaceViewer.normalize(hostname: "host.tail1234.ts.net") == "host.tail1234.ts.net")
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

    @Test func corruptDataHealsToEmpty() {
        #expect(WorkspaceRegistry.decode("{oops".data(using: .utf8)!).isEmpty)
        #expect(WorkspaceRegistry.decode(Data()).isEmpty)
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
}
