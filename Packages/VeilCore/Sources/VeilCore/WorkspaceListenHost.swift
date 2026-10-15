import Foundation

/// The host a workspace server listens on, which is also the address the
/// viewer's machine connects to, so other machines must reach it and this
/// one must be able to bind it.
public enum WorkspaceListenHost {
    /// In order: `workspace_host` from veil.toml, then this node's Tailscale
    /// IPv4 address. nil when neither is available. There is deliberately
    /// no fallback to a LAN name: nvim takes commands on its listen address
    /// without authentication, so how widely it is exposed is the user's
    /// call, made by writing that address in veil.toml.
    ///
    /// The Tailscale address is used rather than the node's MagicDNS name
    /// because a local DNS proxy in fake-IP mode answers that name with an
    /// address this Mac does not own, which nvim cannot bind and which
    /// routes the viewer's connection into the proxy.
    ///
    /// - Parameters:
    ///   - configured: `workspace_host` from veil.toml, if set.
    ///   - tailscaleStatus: stdout of a successful `tailscale status --json`;
    ///     only asked for when nothing is configured.
    public static func resolve(
        configured: String?, tailscaleStatus: () -> Data?
    ) -> String? {
        if let configured, !configured.isEmpty { return configured }
        return tailscaleIPv4Address(inTailscaleStatus: tailscaleStatus())
    }

    /// The first IPv4 entry of `Self.TailscaleIPs`, provided the backend is
    /// running: the report is not guaranteed to fail or to drop the node's
    /// addresses while Tailscale is stopped, so the state is checked
    /// explicitly. IPv6 addresses are skipped: a bare IPv6 address does not
    /// survive the `host:port` form the address travels in.
    private static func tailscaleIPv4Address(inTailscaleStatus json: Data?) -> String? {
        guard let json,
            let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            object["BackendState"] as? String == "Running",
            let selfNode = object["Self"] as? [String: Any],
            let addresses = selfNode["TailscaleIPs"] as? [String]
        else { return nil }
        return addresses.first(where: isIPv4Address)
    }

    private static func isIPv4Address(_ address: String) -> Bool {
        var parsed = in_addr()
        return inet_pton(AF_INET, address, &parsed) == 1
    }
}
