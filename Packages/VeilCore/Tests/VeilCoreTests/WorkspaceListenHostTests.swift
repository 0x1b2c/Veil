import Foundation
import Testing
import VeilCore

struct WorkspaceListenHostTests {
    /// The shape `tailscale status --json` prints, trimmed to the fields
    /// that matter and taken from a real node.
    private func tailscaleStatus(
        backendState: String = "Running",
        ips: [String] = ["100.101.102.103", "fd7a:115c:a1e0:ab12::1"]
    ) -> Data {
        let ipList = ips.map { "\"\($0)\"" }.joined(separator: ", ")
        return Data(
            #"""
            { "BackendState": "\#(backendState)",
              "Self": { "HostName": "2B", "DNSName": "2b.tail1234.ts.net.",
                        "TailscaleIPs": [\#(ipList)] } }
            """#.utf8)
    }

    @Test func configuredHostWins() {
        let host = WorkspaceListenHost.resolve(
            configured: "10.0.0.2", tailscaleStatus: { tailscaleStatus() })
        #expect(host == "10.0.0.2")
    }

    @Test func emptyConfiguredHostIsIgnored() {
        let host = WorkspaceListenHost.resolve(
            configured: "", tailscaleStatus: { tailscaleStatus() })
        #expect(host == "100.101.102.103")
    }

    @Test func tailscaleNodeIsServedOnItsIPv4AddressRatherThanItsName() {
        // A local DNS proxy in fake-IP mode can answer the MagicDNS name
        // with an address this Mac does not own, so nvim could not bind it.
        let host = WorkspaceListenHost.resolve(
            configured: nil, tailscaleStatus: { tailscaleStatus() })
        #expect(host == "100.101.102.103")
    }

    @Test func ipv4AddressIsPickedWhereverItIsListed() {
        let host = WorkspaceListenHost.resolve(
            configured: nil,
            tailscaleStatus: { tailscaleStatus(ips: ["fd7a:115c:a1e0:ab12::1", "100.101.102.103"]) })
        #expect(host == "100.101.102.103")
    }

    @Test func tailscaleWithoutAnIPv4AddressIsUnavailable() {
        let host = WorkspaceListenHost.resolve(
            configured: nil, tailscaleStatus: { tailscaleStatus(ips: ["fd7a:115c:a1e0:ab12::1"]) })
        #expect(host == nil)
    }

    @Test func tailscaleThatIsNotRunningIsUnavailable() {
        for state in ["Stopped", "NeedsLogin", "Starting"] {
            let host = WorkspaceListenHost.resolve(
                configured: nil, tailscaleStatus: { tailscaleStatus(backendState: state) })
            #expect(host == nil, "BackendState \(state)")
        }
    }

    @Test func withoutTailscaleOrConfiguredHostThereIsNoAddress() {
        // No fallback to the Mac's .local name: an nvim listening there
        // takes unauthenticated commands from the whole LAN, so a LAN
        // address is used only when the user writes it in veil.toml.
        let host = WorkspaceListenHost.resolve(configured: nil, tailscaleStatus: { nil })
        #expect(host == nil)
    }

    @Test func unusableTailscaleStatusLeavesNoAddress() {
        for status in [Data("not json".utf8), Data(#"{"Self":{"TailscaleIPs":[]}}"#.utf8)] {
            let host = WorkspaceListenHost.resolve(configured: nil, tailscaleStatus: { status })
            #expect(host == nil)
        }
    }
}

struct WorkspaceConfiguredHostTests {
    @Test(arguments: ["0.0.0.0", "::", "[::]", "*"])
    func aWildcardIsRefused(host: String) throws {
        // It would bind every interface and leave the viewer nothing to
        // connect to.
        let problem = try #require(WorkspaceListenHost.problem(withConfiguredHost: host))
        #expect(problem.contains("every interface"))
    }

    @Test(arguments: ["fd7a:115c:a1e0::4", "[fd7a:115c:a1e0::4]", "::1"])
    func anIPv6AddressIsRefused(host: String) throws {
        let problem = try #require(WorkspaceListenHost.problem(withConfiguredHost: host))
        #expect(problem.contains("IPv6"))
    }

    @Test func aHostWithAPortIsRefused() throws {
        let problem = try #require(WorkspaceListenHost.problem(withConfiguredHost: "a2.local:6700"))
        #expect(problem.contains("port"))
    }

    @Test(arguments: ["100.101.102.103", "192.168.1.20", "a2.local", "localhost", "127.0.0.1"])
    func aSpecificHostIsAccepted(host: String) {
        #expect(WorkspaceListenHost.problem(withConfiguredHost: host) == nil)
    }
}
