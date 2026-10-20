import Foundation

/// Whether an address belongs to this machine.
///
/// A workspace server listens on an address of the machine it runs on.
/// Once that address leaves the machine (Tailscale went down, DHCP handed
/// out another address), the server still runs but nothing can reach it,
/// and an RPC probe to the address cannot tell this from a blocked server:
/// through a proxy that completes every TCP handshake itself, the probe
/// connects and then waits for a reply that never comes. The machine's
/// own interfaces answer the question without the network.
public enum LocalAddresses {
    /// Whether `host`, a name or a numeric address, resolves to an address
    /// assigned to one of this machine's interfaces.
    public static func isOnThisMachine(_ host: String) -> Bool {
        let wanted = resolved(host)
        return !wanted.isEmpty && !wanted.isDisjoint(with: interfaceAddresses())
    }

    private static func resolved(_ host: String) -> Set<String> {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var results: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &results) == 0, let results else { return [] }
        defer { freeaddrinfo(results) }
        var addresses = Set<String>()
        var candidate: UnsafeMutablePointer<addrinfo>? = results
        while let info = candidate {
            if let text = numeric(info.pointee.ai_addr) { addresses.insert(text) }
            candidate = info.pointee.ai_next
        }
        return addresses
    }

    private static func interfaceAddresses() -> Set<String> {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let list else { return [] }
        defer { freeifaddrs(list) }
        var addresses = Set<String>()
        var candidate: UnsafeMutablePointer<ifaddrs>? = list
        while let interface = candidate {
            if let address = interface.pointee.ifa_addr, let text = numeric(address) {
                addresses.insert(text)
            }
            candidate = interface.pointee.ifa_next
        }
        return addresses
    }

    /// The numeric form of an IPv4 or IPv6 socket address, without an IPv6
    /// scope suffix; nil for other families.
    private static func numeric(_ address: UnsafePointer<sockaddr>) -> String? {
        let family = Int32(address.pointee.sa_family)
        guard family == AF_INET || family == AF_INET6 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(address.pointee.sa_len)
        guard
            getnameinfo(
                address, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
        else { return nil }
        let text = String(
            decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return text.split(separator: "%").first.map(String.init)
    }
}
