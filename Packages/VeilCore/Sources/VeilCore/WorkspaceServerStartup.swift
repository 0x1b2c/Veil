import Foundation

/// The wait between spawning a workspace server and handing it files.
public enum WorkspaceServerStartup {
    /// Polls `answers` until the freshly spawned server responds. When it
    /// never does, the process is ended before returning false: veil
    /// started it moments ago and has sent it none of the user's files, so
    /// nothing can be lost, whereas leaving it would leave a server no
    /// registry entry tracks and `veil --workspaces` never shows.
    public static func awaitReady(
        _ process: Process, attempts: Int, interval: TimeInterval, answers: () -> Bool
    ) -> Bool {
        for _ in 0..<attempts {
            if answers() { return true }
            Thread.sleep(forTimeInterval: interval)
        }
        end(process)
        return false
    }

    /// SIGTERM first, so nvim can stop the jobs its startup scripts began;
    /// SIGKILL once `grace` has passed, for an nvim too wedged to act on it.
    private static func end(_ process: Process, grace: TimeInterval = 2) {
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
