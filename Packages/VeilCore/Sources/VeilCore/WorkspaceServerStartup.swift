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
    fileprivate static func end(_ process: Process, grace: TimeInterval = 2) {
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

    /// Ends a server that is still starting when `veil` is interrupted
    /// (Ctrl-C, the pane closing, a plain `kill`), then lets `veil` exit.
    ///
    /// The server runs in its own process group, so the signal that ends
    /// `veil` never reaches it; and it is registered only once it answers.
    /// An interrupted wait would otherwise leave a server that no registry
    /// entry tracks and the next run spawns a second one beside. Like a
    /// server that never becomes ready, it has none of the user's files yet.
    /// Disarm the guard once the server is registered.
    public final class InterruptGuard: @unchecked Sendable {
        private let signals: [Int32]
        private var sources: [DispatchSourceSignal] = []
        private var previous: [Int32: sig_t?] = [:]

        /// - Parameter exit: called with the signal after the server has
        ///   been ended; it should end `veil`.
        public init(
            ending process: Process, signals: [Int32] = [SIGINT, SIGTERM, SIGHUP],
            then exit: @escaping @Sendable (Int32) -> Void
        ) {
            self.signals = signals
            for signo in signals {
                // A dispatch source sees a signal only once its default
                // action, ending the process, is off.
                previous[signo] = signal(signo, SIG_IGN)
                let source = DispatchSource.makeSignalSource(
                    signal: signo, queue: .global(qos: .userInitiated))
                source.setEventHandler {
                    WorkspaceServerStartup.end(process)
                    exit(signo)
                }
                source.resume()
                sources.append(source)
            }
        }

        /// Stops watching and restores what each signal did before.
        public func disarm() {
            sources.forEach { $0.cancel() }
            sources = []
            for signo in signals {
                if let handler = previous.removeValue(forKey: signo) {
                    signal(signo, handler)
                }
            }
        }
    }
}
