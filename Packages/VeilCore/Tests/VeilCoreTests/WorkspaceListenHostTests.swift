import Foundation
import Testing
import VeilCore

struct WorkspaceListenHostTests {
    private func tailscaleStatus(dnsName: String) -> Data {
        #"{ "BackendState": "Running", "Self": { "HostName": "2B", "DNSName": "\#(dnsName)" } }"#
            .data(using: .utf8)!
    }

    @Test func overrideWins() {
        let host = WorkspaceListenHost.resolve(
            override: "10.0.0.2", tailscaleStatus: { tailscaleStatus(dnsName: "2b.ts.net.") },
            bonjourHostName: "Example-Mac")
        #expect(host == "10.0.0.2")
    }

    @Test func emptyOverrideIsIgnored() {
        let host = WorkspaceListenHost.resolve(
            override: "", tailscaleStatus: { tailscaleStatus(dnsName: "2b.tail1234.ts.net.") },
            bonjourHostName: "Example-Mac")
        #expect(host == "2b.tail1234.ts.net")
    }

    @Test func tailscaleNameLosesOnlyItsTrailingDot() {
        let host = WorkspaceListenHost.resolve(
            override: nil, tailscaleStatus: { tailscaleStatus(dnsName: "2b.tail1234.ts.net.") },
            bonjourHostName: "Example-Mac")
        #expect(host == "2b.tail1234.ts.net")
    }

    @Test func withoutTailscaleTheBonjourNameKeepsItsLocalSuffix() {
        // mDNS resolves "<LocalHostName>.local" and nothing shorter: with
        // the suffix stripped the server can neither bind nor be reached.
        let host = WorkspaceListenHost.resolve(
            override: nil, tailscaleStatus: { nil }, bonjourHostName: "Example-Mac")
        #expect(host == "Example-Mac.local")
    }

    @Test func unusableTailscaleStatusFallsBackToBonjour() {
        for status in [Data("not json".utf8), Data(#"{"Self":{"DNSName":""}}"#.utf8)] {
            let host = WorkspaceListenHost.resolve(
                override: nil, tailscaleStatus: { status }, bonjourHostName: "a2")
            #expect(host == "a2.local")
        }
    }

    @Test func noSourceLeavesNoAddress() {
        for bonjourHostName in [nil, ""] as [String?] {
            let host = WorkspaceListenHost.resolve(
                override: nil, tailscaleStatus: { nil }, bonjourHostName: bonjourHostName)
            #expect(host == nil)
        }
    }

    @Test func bonjourHostNameIsTheSystemLocalHostName() throws {
        // Pin the source: `scutil --get LocalHostName` reads the same
        // SystemConfiguration key mDNS advertises.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--get", "LocalHostName"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let expected = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!expected.isEmpty)
        #expect(WorkspaceListenHost.bonjourHostName() == expected)
    }
}
