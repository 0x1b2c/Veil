import Foundation
import Testing
import VeilCore

struct WorkspaceRegistryFileTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-registry-\(UUID().uuidString)")
    }

    @Test func concurrentRunsKeepEachOthersEntries() throws {
        // Each run reads the table, takes a while (probing, spawning), then
        // writes it back with its own entry added, as `veil` does.
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = WorkspaceRegistryFile(directory: directory)
        let runs = 8

        DispatchQueue.concurrentPerform(iterations: runs) { run in
            guard let lock = try? file.lock() else { return }
            defer { lock.unlock() }
            var table = file.load()
            Thread.sleep(forTimeInterval: 0.02)
            table["/project/\(run)"] = .init(host: "127.0.0.1", port: 6700 + run, pid: 100)
            try? file.save(table)
        }

        #expect(file.load().count == runs)
    }

    @Test func savedTableLoadsBack() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = WorkspaceRegistryFile(directory: directory)
        let table: WorkspaceRegistry.Table = ["/p": .init(host: "h", port: 6800, pid: 7)]

        try file.save(table)

        #expect(file.load() == table)
    }

    @Test func missingFileLoadsEmpty() {
        #expect(WorkspaceRegistryFile(directory: temporaryDirectory()).load().isEmpty)
    }
}
