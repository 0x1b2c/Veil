import Testing
import VeilCore

struct VeilCommandLineTests {
    @Test func rendererOnly() {
        let result = VeilCommandLine.parse(["/path/to/Veil", "--veil-renderer", "coretext"])
        #expect(result.renderer == .coretext)
        #expect(result.nvimArgs.isEmpty)
    }

    @Test func rendererWithFile() {
        let result = VeilCommandLine.parse([
            "/path/to/Veil", "--veil-renderer", "coretext", "README.md",
        ])
        #expect(result.renderer == .coretext)
        #expect(result.nvimArgs == ["README.md"])
    }

    @Test func rendererAfterFile() {
        let result = VeilCommandLine.parse([
            "/path/to/Veil", "README.md", "--veil-renderer", "coretext",
        ])
        #expect(result.renderer == .coretext)
        #expect(result.nvimArgs == ["README.md"])
    }

    @Test func defaultRenderer() {
        let result = VeilCommandLine.parse(["/path/to/Veil", "file.txt"])
        #expect(result.renderer == .metal)
        #expect(result.nvimArgs == ["file.txt"])
    }

    @Test func rendererCaseInsensitive() {
        let result = VeilCommandLine.parse(["/path/to/Veil", "--veil-renderer", "CoreText"])
        #expect(result.renderer == .coretext)
    }

    @Test func rendererMetalExplicit() {
        let result = VeilCommandLine.parse(["/path/to/Veil", "--veil-renderer", "metal"])
        #expect(result.renderer == .metal)
    }

    @Test func filtersAppleArgs() {
        let result = VeilCommandLine.parse([
            "/path/to/Veil",
            "-NSDocumentRevisionsDebugMode", "YES",
            "-ApplePersistenceIgnoreState", "YES",
            "file.txt",
        ])
        #expect(result.nvimArgs == ["file.txt"])
        #expect(result.renderer == .metal)
    }

    @Test func filtersAppleArgsWithRenderer() {
        let result = VeilCommandLine.parse([
            "/path/to/Veil",
            "-NSDocumentRevisionsDebugMode", "YES",
            "--veil-renderer", "coretext",
            "file.txt",
        ])
        #expect(result.renderer == .coretext)
        #expect(result.nvimArgs == ["file.txt"])
    }

    @Test func multipleFiles() {
        let result = VeilCommandLine.parse([
            "/path/to/Veil", "--veil-renderer", "coretext",
            "file1.txt", "file2.txt", "file3.txt",
        ])
        #expect(result.renderer == .coretext)
        #expect(result.nvimArgs == ["file1.txt", "file2.txt", "file3.txt"])
    }

    @Test func nvimFlags() {
        let result = VeilCommandLine.parse(["/path/to/Veil", "-d", "file1.txt", "file2.txt"])
        #expect(result.renderer == .metal)
        #expect(result.nvimArgs == ["-d", "file1.txt", "file2.txt"])
    }

    @Test func rendererWithNvimFlags() {
        let result = VeilCommandLine.parse([
            "/path/to/Veil", "--veil-renderer", "coretext",
            "-d", "file1.txt", "file2.txt",
        ])
        #expect(result.renderer == .coretext)
        #expect(result.nvimArgs == ["-d", "file1.txt", "file2.txt"])
    }

    @Test func emptyArgs() {
        let result = VeilCommandLine.parse(["/path/to/Veil"])
        #expect(result.renderer == .metal)
        #expect(result.nvimArgs.isEmpty)
    }

    @Test func rendererMissingValue() {
        let result = VeilCommandLine.parse(["/path/to/Veil", "--veil-renderer"])
        #expect(result.renderer == .metal)
        #expect(result.nvimArgs.isEmpty)
    }

    @Test func rendererEqualsSign() {
        let result = VeilCommandLine.parse([
            "/path/to/Veil", "--veil-renderer=coretext", "file.txt",
        ])
        #expect(result.renderer == .coretext)
        #expect(result.nvimArgs == ["file.txt"])
    }

    @Test func rendererEqualsSignCaseInsensitive() {
        let result = VeilCommandLine.parse(["/path/to/Veil", "--veil-renderer=CoreText"])
        #expect(result.renderer == .coretext)
    }

    @Test func unknownVeilFlag() {
        let result = VeilCommandLine.parse(["/path/to/Veil", "--veil-unknown", "file.txt"])
        #expect(result.nvimArgs == ["file.txt"])
    }

    @Test func connectWithWorkspace() {
        let result = VeilCommandLine.parse([
            "/path/to/veil", "--connect", "2b.example.ts.net:7001", "--workspace", "myproject",
        ])
        #expect(result.remoteAddress == "2b.example.ts.net:7001")
        #expect(result.workspace == "myproject")
        #expect(result.nvimArgs.isEmpty)
    }

    @Test func connectWithoutWorkspace() {
        let result = VeilCommandLine.parse(["/path/to/veil", "--connect", "host:6666"])
        #expect(result.remoteAddress == "host:6666")
        #expect(result.workspace == nil)
        #expect(result.nvimArgs.isEmpty)
    }

    @Test func connectEqualsSign() {
        let result = VeilCommandLine.parse([
            "/path/to/veil", "--connect=host:6666", "--workspace=proj",
        ])
        #expect(result.remoteAddress == "host:6666")
        #expect(result.workspace == "proj")
        #expect(result.nvimArgs.isEmpty)
    }

    @Test func connectMixedWithFiles() {
        let result = VeilCommandLine.parse([
            "/path/to/veil", "--connect", "host:6666", "file.txt",
        ])
        #expect(result.remoteAddress == "host:6666")
        #expect(result.nvimArgs == ["file.txt"])
    }

    @Test func connectWithFilesIsRefused() throws {
        let result = VeilCommandLine.parse([
            "/path/to/veil", "--connect", "host:6666", "file.txt",
        ])
        let message = try #require(result.usageError)
        #expect(message.contains("file.txt"))
        #expect(message.contains("host:6666"))
    }

    @Test func connectAloneIsAccepted() {
        let result = VeilCommandLine.parse([
            "/path/to/veil", "--connect", "host:6666", "--workspace", "proj",
        ])
        #expect(result.usageError == nil)
    }

    @Test func filesWithoutConnectAreAccepted() {
        let result = VeilCommandLine.parse(["/path/to/veil", "-d", "a.txt", "b.txt"])
        #expect(result.usageError == nil)
    }

    @Test func connectMissingValue() {
        let result = VeilCommandLine.parse(["/path/to/veil", "--connect"])
        #expect(result.remoteAddress == nil)
        #expect(result.nvimArgs.isEmpty)
    }

    @Test func workspaceOnly() {
        let result = VeilCommandLine.parse(["/path/to/veil", "--workspace", "proj"])
        #expect(result.remoteAddress == nil)
        #expect(result.workspace == "proj")
        #expect(result.nvimArgs.isEmpty)
    }

    @Test func defaultHasNoRemote() {
        let result = VeilCommandLine.parse(["/path/to/veil", "file.txt"])
        #expect(result.remoteAddress == nil)
        #expect(result.workspace == nil)
        #expect(!result.listWorkspaces)
    }

    @Test("@ws-006 --veil-local keeps the invocation on this machine")
    func veilLocalSkipsWorkspace() {
        let result = VeilCommandLine.parse(["/path/to/veil", "--veil-local", "foo.txt"])
        #expect(!result.mayDivertToWorkspace)
        #expect(result.nvimArgs == ["foo.txt"])
    }

    @Test func plainInvocationMayDivertToWorkspace() {
        let result = VeilCommandLine.parse(["/path/to/veil", "foo.txt"])
        #expect(result.mayDivertToWorkspace)
    }

    @Test func connectNeverDivertsToWorkspace() {
        let result = VeilCommandLine.parse(["/path/to/veil", "--connect", "host:6666"])
        #expect(!result.mayDivertToWorkspace)
    }

    @Test func workspacesFlag() {
        let result = VeilCommandLine.parse(["/path/to/veil", "--workspaces"])
        #expect(result.listWorkspaces)
        #expect(result.nvimArgs.isEmpty)
    }
}
