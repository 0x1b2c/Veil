import Foundation
import Network

/// TCP transport for connecting to a remote nvim instance via
/// Network.framework's NWConnection.
final class SocketTransport: RpcTransport, @unchecked Sendable {
    private let connection: NWConnection
    private let streamContinuation: AsyncStream<Data>.Continuation

    let dataStream: AsyncStream<Data>

    /// Create a transport for the given host and port. The connection is not
    /// started until `waitUntilReady()` is called.
    nonisolated init(host: String, port: UInt16) {
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        self.connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.dataStream = stream
        self.streamContinuation = continuation
    }

    /// Start the TCP connection and block until it is established or fails.
    /// Sets the state handler before calling start() to avoid a race where
    /// the connection reaches .ready before the handler is installed.
    func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.connection.stateUpdateHandler = nil
                    self?.scheduleReceive()
                    cont.resume()
                case .failed(let error):
                    self?.connection.stateUpdateHandler = nil
                    cont.resume(throwing: error)
                case .cancelled:
                    self?.connection.stateUpdateHandler = nil
                    cont.resume(
                        throwing: NWError.posix(.ECANCELED))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    nonisolated func write(_ data: Data) throws {
        connection.send(
            content: data, completion: .contentProcessed({ _ in }))
    }

    nonisolated func close() {
        connection.cancel()
        streamContinuation.finish()
    }

    // MARK: - Private

    nonisolated private func scheduleReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let content, !content.isEmpty {
                self.streamContinuation.yield(content)
            }
            if isComplete || error != nil {
                self.streamContinuation.finish()
                return
            }
            self.scheduleReceive()
        }
    }
}
