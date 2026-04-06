import Foundation

/// Transport that wraps a pair of Foundation pipes (stdin/stdout),
/// used for communicating with a local nvim process.
final class PipeTransport: RpcTransport, @unchecked Sendable {
    private let writePipe: FileHandle
    private let readPipe: FileHandle

    let dataStream: AsyncStream<Data>

    nonisolated init(writePipe: FileHandle, readPipe: FileHandle) {
        self.writePipe = writePipe
        self.readPipe = readPipe
        self.dataStream = readPipe.asyncDataChunks
    }

    nonisolated func write(_ data: Data) throws {
        try writePipe.write(contentsOf: data)
    }

    nonisolated func close() {
        try? writePipe.close()
        // readPipe is owned by the Process's stdout pipe; closing it here
        // would race with the readabilityHandler. Let the Process teardown
        // handle it.
    }
}
