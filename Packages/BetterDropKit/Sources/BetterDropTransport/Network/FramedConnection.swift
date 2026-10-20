import Foundation
import Network
import Synchronization

/// A TCP connection that sends and receives whole records: a four-byte big-endian length, then that many bytes.
public final class FramedConnection: Sendable {
    public enum Failure: Error, Equatable {
        case closed
        case recordTooLarge(Int)
        case failed(String)
    }

    /// Big enough for a chunk and its header, small enough that a bad length can't make us allocate gigabytes.
    static let maximumRecordLength = 4 << 20

    let connection: NWConnection
    private let queue = DispatchQueue(label: "BetterDrop.connection")

    public init(_ connection: NWConnection) {
        self.connection = connection
    }

    public convenience init(to endpoint: NWEndpoint) {
        self.init(NWConnection(to: endpoint, using: NetworkConfiguration.parameters()))
    }

    /// Waits for the connection to be ready (or to fail).
    public func start() async throws {
        let once = Mutex(false)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                @Sendable func finish(_ error: (any Error)?) {
                    guard once.withLock({ done in defer { done = true }; return !done }) else { return }
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
                connection.stateUpdateHandler = { [connection] state in
                    switch state {
                    case .ready: finish(nil)
                    case let .failed(error): finish(Failure.failed(error.localizedDescription))
                    case let .waiting(error):
                        // No route yet: give up rather than wait forever, the caller decides when to retry.
                        connection.cancel()
                        finish(Failure.failed(error.localizedDescription))
                    case .cancelled: finish(Failure.closed)
                    default: break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    /// Hands a record to the network. Synchronous on purpose: callers that number their records (``SecureChannel``)
    /// must not be able to have two sends overtake each other.
    func send(_ record: Data, completion: @escaping @Sendable ((any Error)?) -> Void) {
        var framed = UInt32(record.count).bigEndianBytes
        framed.append(record)
        connection.send(content: framed, completion: .contentProcessed { error in
            completion(error.map { Failure.failed($0.localizedDescription) })
        })
    }

    public func send(_ record: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            send(record) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    /// Reads the next record. Only one reader at a time.
    public func receive() async throws -> Data {
        let header = try await receive(exactly: 4)
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        guard length <= Self.maximumRecordLength else {
            cancel()
            throw Failure.recordTooLarge(length)
        }
        return length == 0 ? Data() : try await receive(exactly: length)
    }

    private func receive(exactly length: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: Failure.failed(error.localizedDescription))
                } else if let data, data.count == length {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: Failure.closed)
                } else {
                    continuation.resume(throwing: Failure.closed)
                }
            }
        }
    }

    /// Whatever bytes come next, up to `maximum`; nil once the other side has finished sending. For HTTP.
    func receiveSome(maximum: Int) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximum) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: Failure.failed(error.localizedDescription))
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    /// Sends bytes as they are, without a length in front. For HTTP.
    func sendRaw(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: Failure.failed(error.localizedDescription)) } else { continuation.resume() }
            })
        }
    }

    /// The address of the other end, when it's an IP address.
    public var remoteHost: String? {
        guard case let .hostPort(host, _) = connection.currentPath?.remoteEndpoint ?? connection.endpoint else { return nil }
        return switch host {
        case let .ipv4(address): "\(address)"
        case let .ipv6(address): "\(address)"
        case let .name(name, _): name
        @unknown default: nil
        }
    }

    public func cancel() {
        connection.cancel()
    }

    /// Who's on the other end, for logs.
    public var remoteDescription: String { "\(connection.endpoint)" }
}

private extension UInt32 {
    var bigEndianBytes: Data { withUnsafeBytes(of: bigEndian) { Data($0) } }
}
