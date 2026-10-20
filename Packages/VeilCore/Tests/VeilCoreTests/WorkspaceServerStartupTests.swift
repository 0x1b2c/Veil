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
            process, timeout: 0.15, interval: 0.05, answers: { false })

        #expect(!ready)
        #expect(!process.isRunning)
    }

    @Test func serverIgnoringTerminationIsEndedAnyway() throws {
        // An nvim wedged in its startup scripts may never act on SIGTERM.
        let process = try start("trap '' TERM; exec /bin/sleep 60")
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }

        let ready = WorkspaceServerStartup.awaitReady(
            process, timeout: 0.5, interval: 0.1, answers: { false })

        #expect(!ready)
        #expect(!process.isRunning)
    }

    @Test func slowProbesDoNotStretchTheWaitPastItsTimeout() throws {
        // Each probe of a server that accepts connections while still
        // starting can take until its own timeout; the wait ends on the
        // clock, not after a fixed number of probes.
        let process = try start("exec /bin/sleep 60")
        defer { if process.isRunning { process.terminate() } }
        let began = Date()

        let ready = WorkspaceServerStartup.awaitReady(
            process, timeout: 0.5, interval: 0.05,
            answers: {
                Thread.sleep(forTimeInterval: 0.3)
                return false
            })

        #expect(!ready)
        #expect(Date().timeIntervalSince(began) < 1.5)
        #expect(!process.isRunning)
    }

    @Test func aServerThatExitsEndsTheWaitAtOnce() throws {
        // nvim exits right away when it cannot listen on the address.
        let process = try start("exit 1")
        let began = Date()

        let ready = WorkspaceServerStartup.awaitReady(
            process, timeout: 5, interval: 0.05, answers: { false })

        #expect(!ready)
        #expect(Date().timeIntervalSince(began) < 1)
    }

    @Test func serverThatAnswersIsLeftRunning() throws {
        let process = try start("exec /bin/sleep 60")
        defer { process.terminate() }
        var probes = 0

        let ready = WorkspaceServerStartup.awaitReady(
            process, timeout: 0.25, interval: 0.05,
            answers: {
                probes += 1
                return probes == 2
            })

        #expect(ready)
        #expect(process.isRunning)
    }
}
