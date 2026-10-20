import CryptoKit
import Foundation

/// The two keys a session encrypts with, one per direction, made fresh for every connection by ``SessionHandshake``.
public struct SessionKeys: Sendable {
    public let sending: SymmetricKey
    public let receiving: SymmetricKey

    public init(sending: SymmetricKey, receiving: SymmetricKey) {
        self.sending = sending
        self.receiving = receiving
    }
}

/// Encrypts and authenticates every record on a connection with ChaCha20-Poly1305.
///
/// Nonces are counters, one per direction, so a record that is replayed, dropped or reordered fails to open and the
/// connection is dropped. Each direction has its own key, so the counters never collide.
public struct SecureSession: Sendable {
    public enum Failure: Error, Equatable {
        case tooShort
        case exhausted
    }

    private let keys: SessionKeys
    private var sent: UInt64 = 0
    private var received: UInt64 = 0

    static let tagLength = 16

    public init(keys: SessionKeys) {
        self.keys = keys
    }

    public mutating func seal(_ plaintext: Data) throws -> Data {
        guard sent < .max else { throw Failure.exhausted }
        let box = try ChaChaPoly.seal(plaintext, using: keys.sending, nonce: Self.nonce(sent))
        sent += 1
        return box.ciphertext + box.tag
    }

    public mutating func open(_ record: Data) throws -> Data {
        guard record.count >= Self.tagLength else { throw Failure.tooShort }
        guard received < .max else { throw Failure.exhausted }
        let split = record.endIndex - Self.tagLength
        let box = try ChaChaPoly.SealedBox(nonce: Self.nonce(received), ciphertext: record[..<split], tag: record[split...])
        let plaintext = try ChaChaPoly.open(box, using: keys.receiving)
        received += 1
        return plaintext
    }

    private static func nonce(_ counter: UInt64) throws -> ChaChaPoly.Nonce {
        try ChaChaPoly.Nonce(data: Data(count: 4) + counter.bigEndianData)
    }
}
