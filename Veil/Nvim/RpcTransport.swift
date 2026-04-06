import Foundation

/// Abstraction over the byte-level transport used by MsgpackRpc.
/// Implementations provide a stream of incoming data chunks and a way
/// to write outgoing data. The protocol is actor-compatible: all
/// requirements are async or nonisolated.
protocol RpcTransport: Sendable {
    /// Incoming data chunks from the remote end (e.g. nvim stdout or TCP socket).
    nonisolated var dataStream: AsyncStream<Data> { get }
    /// Send data to the remote end (e.g. nvim stdin or TCP socket).
    nonisolated func write(_ data: Data) throws
    /// Tear down the connection.
    nonisolated func close()
}
