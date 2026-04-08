import Foundation

/// Checks the GitHub API for the latest Veil release and caches the result.
/// Called once at app startup; the cached version is consumed by `:VeilAppVersion`.
enum UpdateChecker {
    /// The latest release version string (e.g. "0.7"), or nil if the check
    /// hasn't completed or failed.
    private(set) static var latestVersion: String?

    /// Release notes (markdown body) for the latest release, if available.
    private(set) static var releaseNotes: String?

    /// Fetches the latest release tag and notes from GitHub.
    /// Strips the leading "v" prefix if present (e.g. "v0.7" becomes "0.7").
    static func check() async {
        let url = URL(string: "https://api.github.com/repos/rainux/Veil/releases/latest")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tagName = json["tag_name"] as? String
            else { return }
            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            latestVersion = version
            releaseNotes = json["body"] as? String
        } catch {
            // Network failure is silently ignored; latestVersion stays nil.
        }
    }
}
