import Foundation

final class NvimProcess: @unchecked Sendable {
    nonisolated(unsafe) let stdinPipe = Pipe()
    nonisolated(unsafe) let stdoutPipe = Pipe()
    nonisolated(unsafe) let stderrPipe = Pipe()

    private nonisolated(unsafe) var _process: Process?
    private let _processLock = NSLock()
    private let nvimPath: String
    private let cwd: String
    private let appName: String
    private let additionalEnv: [String: String]

    var isRunning: Bool {
        _processLock.lock()
        defer { _processLock.unlock() }
        return _process?.isRunning ?? false
    }

    init(
        nvimPath: String = "",
        cwd: String = NSHomeDirectory(),
        appName: String = "nvim",
        additionalEnv: [String: String] = [:]
    ) {
        self.nvimPath = nvimPath
        self.cwd = cwd
        self.appName = appName
        self.additionalEnv = additionalEnv
    }

    func start() throws {
        let process = Process()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.qualityOfService = .userInteractive
        let binary = resolveNvimBinary()
        process.executableURL = URL(fileURLWithPath: binary)
        var env = Self.loginShellEnvironment()
        env["NVIM_APPNAME"] = appName
        env.merge(additionalEnv) { _, new in new }
        process.environment = env
        process.arguments = ["--embed"]
        try process.run()
        _processLock.lock()
        _process = process
        _processLock.unlock()
    }

    func stop() {
        _processLock.lock()
        let process = _process
        _processLock.unlock()
        guard let process, process.isRunning else { return }
        stdinPipe.fileHandleForWriting.closeFile()
        DispatchQueue.global().async {
            process.waitUntilExit()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { process.terminate() }
        }
    }

    // MARK: - Binary resolution

    private func resolveNvimBinary() -> String {
        if !nvimPath.isEmpty, FileManager.default.isExecutableFile(atPath: nvimPath) {
            return nvimPath
        }
        if let path = Self.findInPath("nvim") { return path }
        for candidate in ["/opt/homebrew/bin/nvim", "/usr/local/bin/nvim"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/usr/local/bin/nvim"
    }

    private static func findInPath(_ binary: String) -> String? {
        guard let pathString = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for dir in pathString.split(separator: ":") {
            let candidate = "\(dir)/\(binary)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    // MARK: - Login shell environment

    static func loginShellEnvironment() -> [String: String] {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = URL(fileURLWithPath: shellPath).lastPathComponent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        var args = ["-l"]
        if shellName != "tcsh" { args.append("-i") }
        let marker = UUID().uuidString
        args.append(contentsOf: ["-c", "echo \(marker) && env"])
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProcessInfo.processInfo.environment
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return ProcessInfo.processInfo.environment
        }
        guard let markerRange = output.range(of: marker) else {
            return ProcessInfo.processInfo.environment
        }
        let envString = output[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        var env: [String: String] = [:]
        for line in envString.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { env[String(parts[0])] = String(parts[1]) }
        }
        return env.isEmpty ? ProcessInfo.processInfo.environment : env
    }
}
