import Foundation

/// The wait between spawning a workspace server and handing it files.
public enum WorkspaceServerStartup {
    /// Polls `answers` until the freshly spawned server responds, for at
    /// most `timeout` seconds by the clock, however long each probe takes.
    /// When it never does, the process is ended before returning false:
    /// veil started it moments ago and has sent it none of the user's
    /// files, so nothing can be lost, whereas leaving it would leave a
    /// server no registry entry tracks and `veil --veil-workspaces` never
    /// shows. A process that exits on its own (an nvim that cannot listen
    /// on the address) ends the wait at once.
    public static func awaitReady(
        _ process: Process, timeout: TimeInterval, interval: TimeInterval, answers: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if answers() { return true }
            if Date().addingTimeInterval(interval) >= deadline { break }
            Thread.sleep(forTimeInterval: interval)
        }
        end(process)
        return false
    }

    /// SIGTERM first, so nvim can stop the jobs its startup scripts began;
    /// SIGKILL once `grace` has passed, for an nvim too wedged to act on it.
    private static func end(_ process: Process, grace: TimeInterval = 2) {
        // One that already exited has been reaped; its pid may name another
        // process by now.
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(grace)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }
}
