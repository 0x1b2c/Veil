import Foundation
import Testing
import VeilCore

struct LocalAddressesTests {
    @Test func loopbackIsOnThisMachine() {
        #expect(LocalAddresses.isOnThisMachine("127.0.0.1"))
        #expect(LocalAddresses.isOnThisMachine("localhost"))
    }

    @Test func anAddressOnNoLocalInterfaceIsNot() {
        // A documentation address no machine is assigned. Through a proxy
        // that completes every TCP handshake itself, a connection to it
        // succeeds and then hangs, so only the interfaces can tell.
        #expect(!LocalAddresses.isOnThisMachine("192.0.2.1"))
    }

    @Test func aNameThatDoesNotResolveIsNot() {
        #expect(!LocalAddresses.isOnThisMachine("no-such-host.invalid"))
    }
}
