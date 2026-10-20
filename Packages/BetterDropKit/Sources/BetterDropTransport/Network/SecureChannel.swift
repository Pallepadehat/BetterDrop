import BetterDropCore
import Foundation

/// A ``FramedConnection`` after the handshake: every ``Message`` is sealed on the way out and opened on the way in.
public actor SecureChannel {
    private let connection: FramedConnection
    private var session: SecureSession

    init(connection: FramedConnection, keys: SessionKeys) {
        self.connection = connection
        session = SecureSession(keys: keys)
    }

    public func send(_ message: Message) async throws {
        let record = try session.seal(MessageCodec.encode(message))
        // Sealing numbers the record, so it has to reach the connection before anything sealed after it. The
        // continuation's body runs right here on the actor, with no suspension in between.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(record) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    public func receive() async throws -> Message {
        let record = try await connection.receive()
        return try MessageCodec.decode(session.open(record))
    }

    public nonisolated func close() {
        connection.cancel()
    }
}
