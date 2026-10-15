import Foundation
import Testing
import VeilCore

struct WorkspaceListenHostTests {
    private func tailscaleStatus(dnsName: String) -> Data {
        #"{ "BackendState": "Running", "Self": { "HostName": "2B", "DNSName": "\#(dnsName)" } }"#
            .data(using: .utf8)!
    }

    @Test func configuredHostWins() {
        let host = WorkspaceListenHost.resolve(
            configured: "10.0.0.2", tailscaleStatus: { tailscaleStatus(dnsName: "2b.ts.net.") })
        #expect(host == "10.0.0.2")
    }

    @Test func emptyConfiguredHostIsIgnored() {
        let host = WorkspaceListenHost.resolve(
            configured: "", tailscaleStatus: { tailscaleStatus(dnsName: "2b.tail1234.ts.net.") })
        #expect(host == "2b.tail1234.ts.net")
    }

    @Test func tailscaleNameLosesOnlyItsTrailingDot() {
        let host = WorkspaceListenHost.resolve(
            configured: nil, tailscaleStatus: { tailscaleStatus(dnsName: "2b.tail1234.ts.net.") })
        #expect(host == "2b.tail1234.ts.net")
    }

    @Test func withoutTailscaleOrConfiguredHostThereIsNoAddress() {
        // No fallback to the Mac's .local name: an nvim listening there
        // takes unauthenticated commands from the whole LAN, so a LAN
        // address is used only when the user writes it in veil.toml.
        let host = WorkspaceListenHost.resolve(configured: nil, tailscaleStatus: { nil })
        #expect(host == nil)
    }

    @Test func unusableTailscaleStatusLeavesNoAddress() {
        for status in [Data("not json".utf8), Data(#"{"Self":{"DNSName":""}}"#.utf8)] {
            let host = WorkspaceListenHost.resolve(configured: nil, tailscaleStatus: { status })
            #expect(host == nil)
        }
    }
}
