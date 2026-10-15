import Foundation
import Testing
import VeilCore

struct VeilConfigFilePathTests {
    private let home = URL(fileURLWithPath: "/Users/someone")

    @Test func defaultsToDotConfigUnderHome() {
        let path = VeilConfigFile.path(environment: [:], home: home)
        #expect(path.path == "/Users/someone/.config/veil/veil.toml")
    }

    @Test func veilConfigOverridesTheLocation() {
        let path = VeilConfigFile.path(
            environment: ["VEIL_CONFIG": "/nix/store/abc-veil.toml"], home: home)
        #expect(path.path == "/nix/store/abc-veil.toml")
    }

    @Test func veilConfigExpandsATilde() {
        let path = VeilConfigFile.path(environment: ["VEIL_CONFIG": "~/veil.toml"], home: home)
        #expect(path.path == NSHomeDirectory() + "/veil.toml")
    }

    @Test func emptyVeilConfigIsIgnored() {
        let path = VeilConfigFile.path(environment: ["VEIL_CONFIG": ""], home: home)
        #expect(path.path == "/Users/someone/.config/veil/veil.toml")
    }

    @Test func xdgConfigHomeIsNotConsulted() {
        // The app has always read ~/.config/veil/veil.toml whatever
        // XDG_CONFIG_HOME says; the CLI reads the same file.
        let path = VeilConfigFile.path(
            environment: ["XDG_CONFIG_HOME": "/Users/someone/xdg"], home: home)
        #expect(path.path == "/Users/someone/.config/veil/veil.toml")
    }
}

struct VeilConfigFileWorkspaceHostTests {
    private func configFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-config-\(UUID().uuidString).toml")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func readsTheTopLevelWorkspaceHost() throws {
        let url = try configFile(
            """
            line_height = 1.2
            workspace_host = "192.168.1.20"

            [keyboard]
            option_as_meta = "left"
            """)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try VeilConfigFile.workspaceHost(inFileAt: url) == "192.168.1.20")
    }

    @Test func absentKeyLeavesItUnset() throws {
        let url = try configFile("ligatures = false\n")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try VeilConfigFile.workspaceHost(inFileAt: url) == nil)
    }

    @Test func emptyValueLeavesItUnset() throws {
        let url = try configFile("workspace_host = \"\"\n")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try VeilConfigFile.workspaceHost(inFileAt: url) == nil)
    }

    @Test func keyInsideATableIsNotTheSetting() throws {
        // Written below [keyboard], the key belongs to that table.
        let url = try configFile("[keyboard]\nworkspace_host = \"10.0.0.2\"\n")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try VeilConfigFile.workspaceHost(inFileAt: url) == nil)
    }

    @Test func missingFileLeavesItUnset() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-config-\(UUID().uuidString).toml")
        #expect(try VeilConfigFile.workspaceHost(inFileAt: url) == nil)
    }

    @Test func malformedFileIsAnError() throws {
        let url = try configFile("workspace_host = \n")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: VeilConfigFile.ReadError.self) {
            try VeilConfigFile.workspaceHost(inFileAt: url)
        }
    }

    @Test func nonStringValueIsAnError() throws {
        let url = try configFile("workspace_host = 42\n")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: VeilConfigFile.ReadError.self) {
            try VeilConfigFile.workspaceHost(inFileAt: url)
        }
    }
}
