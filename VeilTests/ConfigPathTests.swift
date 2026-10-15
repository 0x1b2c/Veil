import Foundation
import Testing

@testable import Veil

/// The app reads veil.toml where it always has, now through the rules it
/// shares with the CLI: `$VEIL_CONFIG` when set and non-empty, else
/// `~/.config/veil/veil.toml`, never under `$XDG_CONFIG_HOME`.
struct ConfigPathTests {
    @Test func appReadsTheConfigWhereItAlwaysHas() {
        let environment = ProcessInfo.processInfo.environment
        let expected: URL
        if let override = environment["VEIL_CONFIG"], !override.isEmpty {
            expected = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        } else {
            expected = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/veil/veil.toml")
        }
        #expect(VeilConfig.userConfigPath == expected)
    }
}
