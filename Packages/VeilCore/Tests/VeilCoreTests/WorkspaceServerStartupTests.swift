import Foundation
import Testing
import VeilCore

struct WorkspaceServerStartupTests {
    private func start(_ script: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        return process
    }

    @Test func serverThatNeverAnswersIsEnded() throws {
        let process = try start("exec /bin/sleep 60")
        defer { if process.isRunning { process.terminate() } }

        let ready = WorkspaceServerStartup.awaitReady(
            process, attempts: 3, interval: 0.05, answers: { false })

        #expect(!ready)
        #expect(!process.isRunning)
    }

    @Test func serverIgnoringTerminationIsEndedAnyway() throws {
        // An nvim wedged in its startup scripts may never act on SIGTERM.
        let process = try start("trap '' TERM; exec /bin/sleep 60")
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }

        let ready = WorkspaceServerStartup.awaitReady(
            process, attempts: 5, interval: 0.1, answers: { false })

        #expect(!ready)
        #expect(!process.isRunning)
    }

    @Test func serverThatAnswersIsLeftRunning() throws {
        let process = try start("exec /bin/sleep 60")
        defer { process.terminate() }
        var probes = 0

        let ready = WorkspaceServerStartup.awaitReady(
            process, attempts: 5, interval: 0.05,
            answers: {
                probes += 1
                return probes == 2
            })

        #expect(ready)
        #expect(process.isRunning)
    }
}
