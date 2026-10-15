import Foundation
import SystemConfiguration

/// The host a workspace server listens on, which is also the address the
/// viewer's machine connects to, so it must be a name other machines can
/// resolve and this one can bind.
public enum WorkspaceListenHost {
    /// In order: an explicit override (`VEIL_WORKSPACE_HOST`), this node's
    /// Tailscale MagicDNS name, then the Bonjour name
    /// `<LocalHostName>.local`. nil when none of them is available.
    ///
    /// - Parameters:
    ///   - override: the value of `VEIL_WORKSPACE_HOST`, if set.
    ///   - tailscaleStatus: stdout of a successful `tailscale status --json`;
    ///     only asked for when there is no override.
    ///   - bonjourHostName: see `bonjourHostName()`.
    public static func resolve(
        override: String?, tailscaleStatus: () -> Data?, bonjourHostName: String?
    ) -> String? {
        if let override, !override.isEmpty { return override }
        if let name = magicDNSName(inTailscaleStatus: tailscaleStatus()) { return name }
        guard let bonjourHostName, !bonjourHostName.isEmpty else { return nil }
        return "\(bonjourHostName).local"
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

    /// SystemConfiguration's LocalHostName, the name this Mac answers to
    /// over mDNS (System Settings > General > Sharing > Local hostname),
    /// without the `.local` suffix. nil when it is not set.
    public static func bonjourHostName() -> String? {
        SCDynamicStoreCopyLocalHostName(nil) as String?
    }
}
