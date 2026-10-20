import Testing
import VeilCore

struct RemoteAddressTests {
    @Test(arguments: [
        ("100.101.102.103:6700", "100.101.102.103", 6700),
        ("tcp://100.101.102.103:6700", "100.101.102.103", 6700),
        ("a2.local:6701", "a2.local", 6701),
        ("localhost:6666", "localhost", 6666),
        ("2b.tail1234.ts.net:6702", "2b.tail1234.ts.net", 6702),
        ("tcp://2b.tail1234.ts.net:6702", "2b.tail1234.ts.net", 6702),
        ("studio:7000", "studio", 7000),
        ("[fd7a:115c:a1e0:ab12::1]:6703", "fd7a:115c:a1e0:ab12::1", 6703),
    ])
    func hostnamesAndAddressesBothParse(input: String, host: String, port: Int) {
        let parsed = RemoteAddress.parse(input)
        #expect(parsed?.host == host)
        #expect(parsed.map { Int($0.port) } == port)
    }

    @Test(arguments: [
        "", "100.101.102.103", "a2.local:", ":6700", "a2.local:0", "a2.local:65536", "a2.local:port",
        "udp://a2.local:6700",
    ])
    func malformedAddressesAreRefused(input: String) {
        #expect(RemoteAddress.parse(input) == nil)
    }
}
