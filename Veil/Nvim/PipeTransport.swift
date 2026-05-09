import Foundation

/// Transport that wraps a pair of Foundation pipes (stdin/stdout),
/// used for communicating with a local nvim process.
final class PipeTransport: RpcTransport, @unchecked Sendable {
    private let writePipe: FileHandle
    private let readPipe: FileHandle
    private let streamContinuation: AsyncStream<Data>.Continuation

    private let finishLock = NSLock()
    nonisolated(unsafe) private var isFinished = false

    let dataStream: AsyncStream<Data>

    nonisolated init(writePipe: FileHandle, readPipe: FileHandle) {
        self.writePipe = writePipe
        self.readPipe = readPipe

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.dataStream = stream
        self.streamContinuation = continuation

        readPipe.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                self.finishStream()
                return
            }
            self.streamContinuation.yield(data)
        }
    }

    nonisolated func write(_ data: Data) throws {
        try writePipe.write(contentsOf: data)
    }

    nonisolated func close() {
        try? writePipe.close()
        // readPipe is owned by the Process's stdout pipe; closing it here
        // would race with the readabilityHandler. Let the Process teardown
        // handle it.
        finishStream()
    }

    // MARK: - Private

    /// Idempotent termination: detaches the readabilityHandler and finishes
    /// the stream exactly once. The handler must be cleared before finishing
    /// because Foundation can otherwise keep invoking it with empty data
    /// after the remote pipe closes, busy-looping the dispatch queue.
    nonisolated private func finishStream() {
        finishLock.lock()
        if isFinished {
            finishLock.unlock()
            return
        }
        isFinished = true
        finishLock.unlock()

        readPipe.readabilityHandler = nil
        streamContinuation.finish()
    }
}
