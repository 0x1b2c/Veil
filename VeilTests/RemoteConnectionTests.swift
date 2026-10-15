import AppKit
import Testing

@testable import Veil

/// Drives the real connect path in the test host: port 1 on the loopback
/// interface refuses the connection at once, so the window ends up showing
/// the error, as after a timed-out `veil --connect`.
@MainActor
@Suite(.serialized)
struct RemoteConnectionTests {
    private let address = "127.0.0.1:1"

    @Test("@ws-005 connecting again to an address whose window failed replaces that window")
    func reconnectReplacesFailedWindow() async throws {
        let appDelegate = try #require(NSApp.delegate as? AppDelegate)
        appDelegate.connectOrActivateRemoteWindow(address: address, workspace: "ws-005")
        let failed = try #require(remoteDocuments().first)
        try await waitUntil { failed.remoteConnectionFailed }

        appDelegate.connectOrActivateRemoteWindow(address: address, workspace: "ws-005")

        let current = remoteDocuments()
        defer { current.forEach { $0.close() } }
        #expect(!current.contains(failed))
        #expect(current.count == 1)
    }

    @Test func connectingAgainWhileTheFirstAttemptRunsKeepsOneWindow() async throws {
        let appDelegate = try #require(NSApp.delegate as? AppDelegate)
        appDelegate.connectOrActivateRemoteWindow(address: address, workspace: nil)
        let first = try #require(remoteDocuments().first)

        appDelegate.connectOrActivateRemoteWindow(address: address, workspace: nil)

        let current = remoteDocuments()
        defer { current.forEach { $0.close() } }
        #expect(current == [first])
    }

    private func remoteDocuments() -> [WindowDocument] {
        NSDocumentController.shared.documents
            .compactMap { $0 as? WindowDocument }
            .filter { $0.isRemote && $0.remoteAddress == address }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(condition())
    }
}
