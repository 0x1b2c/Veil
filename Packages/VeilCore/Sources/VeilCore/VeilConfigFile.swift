import Foundation
import TOML

/// `veil.toml`, which the app reads for its own settings and the CLI for
/// `workspace_host`. Both find it through `path(environment:home:)`.
public enum VeilConfigFile {
    /// Why `workspace_host` could not be read from an existing file.
    public struct ReadError: Error, Equatable {
        public var message: String
    }

    /// Where the config lives.
    ///
    /// `$VEIL_CONFIG` overrides the location. This lets the config live
    /// somewhere other than the home directory, which is useful for
    /// immutable or managed setups (e.g. Nix) that point Veil at a
    /// generated, read-only config instead of seeding and editing the
    /// default path. Otherwise it is `~/.config/veil/veil.toml`;
    /// `$XDG_CONFIG_HOME` is not consulted.
    public static func path(environment: [String: String], home: URL) -> URL {
        if let override = environment["VEIL_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return home.appendingPathComponent(".config/veil/veil.toml")
    }

    /// The top-level `workspace_host` of the file at `url`; nil when the
    /// file does not exist or the key is absent or empty.
    public static func workspaceHost(inFileAt url: URL) throws(ReadError) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ReadError(message: error.localizedDescription)
        }
        do {
            let host = try TOMLDecoder().decode(WorkspaceSettings.self, from: text).workspace_host
            return host?.isEmpty == false ? host : nil
        } catch {
            throw ReadError(message: "\(error)")
        }
    }

    /// The keys the CLI reads; every other key is the app's and is ignored.
    private struct WorkspaceSettings: Decodable {
        var workspace_host: String?
    }
}
