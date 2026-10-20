import Foundation
import Testing
import VeilCore

/// The translation is checked against a real nvim: what matters is the
/// state the server ends up in, not the text of the expression.
@Suite(.enabled(if: HeadlessNvim.isAvailable, "needs nvim on PATH"))
struct WorkspaceNvimArgumentsTests {
    @Test("@ws-004 gvimdiff arguments show the two files as a diff in the workspace")
    func diffTwoFiles() throws {
        let nvim = try HeadlessNvim()
        defer { nvim.stop() }
        try nvim.open(["-d", "a.txt", "b.txt"])

        #expect(try nvim.windowsInCurrentTab() == ["a.txt:diff", "b.txt:diff"])
        #expect(try nvim.bufferNames() == ["a.txt", "b.txt"])
    }

    @Test func diffThreeFilesKeepsArgumentOrderWithCursorInFirst() throws {
        let nvim = try HeadlessNvim()
        defer { nvim.stop() }
        try nvim.open(["-d", "a.txt", "b.txt", "c.txt"])

        #expect(
            try nvim.windowsInCurrentTab() == ["a.txt:diff", "b.txt:diff", "c.txt:diff"])
        #expect(try nvim.eval("expand('%:t')") == "a.txt")
    }

    @Test func diffOfAFileAlreadyOnScreenOpensInANewTab() throws {
        let nvim = try HeadlessNvim()
        defer { nvim.stop() }
        try nvim.open(["a.txt"])
        _ = try nvim.eval("execute('vsplit c.txt')")
        try nvim.open(["-d", "a.txt", "b.txt"])

        #expect(try nvim.windowsInCurrentTab() == ["a.txt:diff", "b.txt:diff"])
        #expect(try nvim.eval("tabpagenr('$')") == "2")
        #expect(try nvim.eval("tabpagenr()") == "2")
    }

    @Test func diffOnAFreshServerLeavesNoEmptyTab() throws {
        let nvim = try HeadlessNvim()
        defer { nvim.stop() }
        try nvim.open(["-d", "a.txt", "b.txt"])

        #expect(try nvim.eval("tabpagenr('$')") == "1")
    }

    @Test func diffSingleFileTurnsOnDiffMode() throws {
        let nvim = try HeadlessNvim()
        defer { nvim.stop() }
        try nvim.open(["-d", "a.txt"])

        #expect(try nvim.windowsInCurrentTab() == ["a.txt:diff"])
    }

    @Test func plusCommandRunsAfterTheFileOpens() throws {
        let nvim = try HeadlessNvim()
        defer { nvim.stop() }
        try nvim.open(["+2", "a.txt"])

        #expect(try nvim.eval("expand('%:t') .. ':' .. line('.')") == "a.txt:2")
        #expect(try nvim.bufferNames() == ["a.txt"])
    }

    @Test func aFailingPlusCommandLeavesTheFileOpenAndTheLaterCommandsRun() throws {
        let nvim = try HeadlessNvim()
        defer { nvim.stop() }
        let reply = try nvim.open(["+/NOPE", "a.txt", "+2"])

        #expect(
            WorkspaceNvimArguments.commandFailures(inReply: reply) == [
                "/NOPE: E486: Pattern not found: NOPE"
            ])
        #expect(try nvim.eval("expand('%:t') .. ':' .. line('.')") == "a.txt:2")
        #expect(try nvim.eval("execute('messages')").contains("E486"))
    }

    @Test func aFileLeftWithASwapFileOpensReadOnlyWithARecoverHint() throws {
        let swapDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-swap-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(
            at: swapDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: swapDirectory) }
        // A server that dies with an unsaved change leaves its swap file.
        let crashed = try HeadlessNvim(swapDirectory: swapDirectory)
        defer { crashed.stop() }
        try crashed.open(["a.txt"])
        _ = try crashed.eval("execute('normal! ix') .. execute('preserve')")
        crashed.kill()

        let nvim = try HeadlessNvim(swapDirectory: swapDirectory)
        defer { nvim.stop() }
        let file = crashed.directory.appendingPathComponent("a.txt").path
        let reply = try nvim.open([file, "+2"])

        #expect(try nvim.eval("expand('%:t') .. ':' .. &readonly") == "a.txt:1")
        #expect(try nvim.eval("line('.')") == "2")
        let notes = WorkspaceNvimArguments.commandFailures(inReply: reply)
        #expect(notes.count == 1)
        #expect(notes.first?.contains(":recover") == true)
    }

    @Test func barePlusGoesToLastLine() throws {
        let nvim = try HeadlessNvim()
        defer { nvim.stop() }
        try nvim.open(["a.txt", "+"])

        #expect(try nvim.eval("line('.')") == "3")
    }

    @Test func readonlyCoversFilesNotYetLoaded() throws {
        let nvim = try HeadlessNvim()
        defer { nvim.stop() }
        try nvim.open(["-R", "a.txt", "b.txt"])

        #expect(try nvim.eval("expand('%:t') .. ':' .. &readonly") == "a.txt:1")
        _ = try nvim.eval("execute('next')")
        #expect(try nvim.eval("expand('%:t') .. ':' .. &readonly") == "b.txt:1")
    }

    @Test func awkwardFileNamesSurviveQuotingAndEscaping() throws {
        let nvim = try HeadlessNvim()
        defer { nvim.stop() }
        try nvim.open(["-d", "it's a.txt", "100% #1|x.txt"])

        #expect(
            try nvim.windowsInCurrentTab() == ["it's a.txt:diff", "100% #1|x.txt:diff"])
    }

    @Test func argumentsAfterDoubleDashAreFiles() throws {
        let nvim = try HeadlessNvim()
        defer { nvim.stop() }
        try nvim.open(["--", "-d", "+2"])

        #expect(try nvim.bufferNames() == ["+2", "-d"])
        #expect(try nvim.windowsInCurrentTab() == ["-d:nodiff"])
    }
}

struct WorkspaceNvimArgumentsRefusalTests {
    @Test(arguments: ["-u", "-i", "--clean", "-O", "-c", "-"])
    func optionsThatCannotReachARunningNvimAreRefused(option: String) {
        #expect(throws: WorkspaceNvimArguments.UnsupportedArgument(argument: option)) {
            try WorkspaceNvimArguments.remoteExpression(for: [option, "a.txt"], cwd: "/tmp")
        }
    }

    @Test func nothingToSendWithoutArguments() throws {
        #expect(try WorkspaceNvimArguments.remoteExpression(for: [], cwd: "/tmp") == nil)
    }
}

/// An nvim of this test's own, listening on a socket in a fresh temporary
/// directory that also holds the files the tests open.
final class HeadlessNvim {
    static var isAvailable: Bool {
        (try? run(["--version"]).status) == 0
    }

    let directory: URL
    private let socket: String
    private let process = Process()

    /// With `swapDirectory`, the server keeps swap files there, as a
    /// workspace server does in its user's swap directory; otherwise it
    /// keeps none.
    init(swapDirectory: URL? = nil) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-nvim-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["a.txt", "b.txt", "c.txt", "it's a.txt", "100% #1|x.txt", "-d", "+2"] {
            let body = name == "b.txt" ? "1\nB\n3\n" : "1\n2\n3\n"
            try body.write(
                to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        socket = directory.appendingPathComponent("nvim.sock").path
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let swap = swapDirectory.map { ["--cmd", "set directory=\($0.path)//"] } ?? ["-n"]
        process.arguments = ["nvim", "--clean", "--headless"] + swap + ["--listen", socket]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        for _ in 0..<50 {
            if (try? eval("1")) == "1" { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        stop()
        throw Failure(message: "nvim did not start listening on \(socket)")
    }

    /// Ends the server the way a crash would, leaving its swap files.
    func kill() {
        Darwin.kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
    }

    func stop() {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Sends `nvimArgs` the way `veil` does for a workspace, returning
    /// the server's reply.
    @discardableResult
    func open(_ nvimArgs: [String]) throws -> String {
        let expression = try #require(
            try WorkspaceNvimArguments.remoteExpression(for: nvimArgs, cwd: directory.path))
        return try eval(expression)
    }

    func eval(_ expression: String) throws -> String {
        let result = try Self.run(["--server", socket, "--remote-expr", expression])
        guard result.status == 0 else {
            throw Failure(message: "--remote-expr failed: \(result.stderr)")
        }
        return result.stdout
    }

    /// `<file>:diff` or `<file>:nodiff` per window, left to right.
    func windowsInCurrentTab() throws -> [String] {
        try lines(
            "join(map(gettabinfo(tabpagenr())[0].windows, {_, w -> "
                + "fnamemodify(bufname(winbufnr(w)), ':t') .. ':' "
                + ".. (getwinvar(w, '&diff') ? 'diff' : 'nodiff')}), \"\\n\")")
    }

    /// Names of all buffers that have one, sorted.
    func bufferNames() throws -> [String] {
        try lines(
            "join(sort(map(filter(getbufinfo(), {_, b -> b.name != ''}), "
                + "{_, b -> fnamemodify(b.name, ':t')})), \"\\n\")")
    }

    private func lines(_ expression: String) throws -> [String] {
        try eval(expression).split(separator: "\n").map(String.init)
    }

    private static func run(_ arguments: [String]) throws -> (
        status: Int32, stdout: String, stderr: String
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["nvim"] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: output, as: UTF8.self),
            String(decoding: errorOutput, as: UTF8.self)
        )
    }

    struct Failure: Error, CustomStringConvertible {
        var message: String
        var description: String { message }
    }
}
