import Foundation

/// The host a workspace server listens on, which is also the address the
/// viewer's machine connects to, so it must be a name other machines can
/// resolve and this one can bind.
public enum WorkspaceListenHost {
    /// In order: `workspace_host` from veil.toml, then this node's Tailscale
    /// MagicDNS name. nil when neither is available. There is deliberately
    /// no fallback to a LAN name: nvim takes commands on its listen address
    /// without authentication, so how widely it is exposed is the user's
    /// call, made by writing that address in veil.toml.
    ///
    /// - Parameters:
    ///   - configured: `workspace_host` from veil.toml, if set.
    ///   - tailscaleStatus: stdout of a successful `tailscale status --json`;
    ///     only asked for when nothing is configured.
    public static func resolve(
        configured: String?, tailscaleStatus: () -> Data?
    ) -> String? {
        if let configured, !configured.isEmpty { return configured }
        return magicDNSName(inTailscaleStatus: tailscaleStatus())
    }

    /// `Self.DNSName` of the status report, without the trailing dot of
    /// its fully qualified form.
    private static func magicDNSName(inTailscaleStatus json: Data?) -> String? {
        guard let json,
            let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            let selfNode = object["Self"] as? [String: Any],
            let dnsName = selfNode["DNSName"] as? String,
            !dnsName.isEmpty
        else { return nil }
        return dnsName.hasSuffix(".") ? String(dnsName.dropLast()) : dnsName
    }

}
