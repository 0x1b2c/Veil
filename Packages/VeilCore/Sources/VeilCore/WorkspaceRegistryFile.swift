import Foundation

/// `registry.json` in veil's state directory (see `WorkspaceRegistry` for
/// its schema). A run reads the table, probes and perhaps spawns a server,
/// then writes the table back; two runs doing that at once would each
/// write back a table without the other's entry. Holding `lock()` across
/// the whole cycle serializes them.
public struct WorkspaceRegistryFile: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var url: URL { directory.appendingPathComponent("registry.json") }

    /// Never deleted: a run that removed it while another waited on it
    /// would let a third lock a fresh file alongside them.
    private var lockURL: URL { directory.appendingPathComponent("registry.lock") }

    public func load() -> WorkspaceRegistry.Table {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return WorkspaceRegistry.decode(data)
    }

    /// Atomic replace (temp file + rename), so a reader that does not
    /// take the lock, such as `veil --workspaces`, never observes a
    /// half-written registry.
    public func save(_ table: WorkspaceRegistry.Table) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try WorkspaceRegistry.encode(table)
        let tmp = directory.appendingPathComponent("registry.json.\(UUID().uuidString)")
        try data.write(to: tmp)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    /// Blocks until this caller holds the registry exclusively. The lock
    /// is an `flock` on its own open file, so it also excludes other
    /// callers in the same process, and the system releases it if the
    /// process dies holding it.
    public func lock() throws -> Lock {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else {
                let code = errno
                close(descriptor)
                throw POSIXError(.init(rawValue: code) ?? .EIO)
            }
        }
        return Lock(descriptor: descriptor)
    }

    public final class Lock {
        private var descriptor: Int32

        fileprivate init(descriptor: Int32) {
            self.descriptor = descriptor
        }

        /// Closing the descriptor drops the `flock`.
        public func unlock() {
            guard descriptor >= 0 else { return }
            close(descriptor)
            descriptor = -1
        }

        deinit { unlock() }
    }
}
