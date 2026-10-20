import Foundation

/// The `host:port` address of a remote nvim, as `veil --veil-connect`
/// passes it and the manual connect dialog accepts it.
public enum RemoteAddress {
    /// Splits `host:port`, `tcp://host:port`, or `[ipv6]:port` into host and
    /// port; nil for anything else. The host may be a name (`a2.local`,
    /// `localhost`, a MagicDNS name) or an address. The input always goes
    /// through `URL` with the `tcp` scheme, because a bare `name:port` parses
    /// as a URL whose scheme is the name and whose host is missing.
    public static func parse(_ input: String) -> (host: String, port: UInt16)? {
        let scheme = "tcp://"
        let withScheme = input.hasPrefix(scheme) ? input : scheme + input
        guard let components = URLComponents(string: withScheme),
            components.scheme == "tcp",
            let host = components.host.map(unbracketed), !host.isEmpty,
            let port = components.port, (1...65535).contains(port),
            components.path.isEmpty, components.query == nil
        else { return nil }
        return (host, UInt16(port))
    }

    /// `URLComponents` keeps the brackets around an IPv6 host; a connection
    /// wants the bare address.
    private static func unbracketed(_ host: String) -> String {
        host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    }
}
