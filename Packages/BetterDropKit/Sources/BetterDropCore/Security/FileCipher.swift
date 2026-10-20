import CryptoKit
import Foundation

/// Encrypts whole files for the background path, where big files go over plain HTTP so iOS can keep moving them
/// after you leave the app.
///
/// Each file gets its own key, derived from the pairing secret and a random salt, so nobody without the pairing can
/// read it or make one we'd accept. The file is cut into 1 MB chunks, each sealed with ChaCha20-Poly1305. A chunk's
/// nonce carries its number and whether it's the last, so chunks can't be reordered, and a file that's been cut
/// short fails instead of arriving truncated.
///
///     file  =  chunk(0) chunk(1) … chunk(n, final)        each chunk = ciphertext | 16-byte tag
public enum FileCipher {
    public static let chunkSize = 1 << 20
    static let tagLength = 16

    public enum Failure: Error, Equatable {
        case damaged
        case truncated
    }

    /// A fresh random salt for a new file.
    public static func makeSalt() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public static func key(secret: Data, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret), salt: salt,
                               info: Data("BetterDrop file v1".utf8), outputByteCount: 32)
    }

    /// How big the encrypted file is, so it can be sent with a Content-Length.
    public static func encryptedSize(of plainSize: Int64) -> Int64 {
        let chunks = max(1, (plainSize + Int64(chunkSize) - 1) / Int64(chunkSize))
        return plainSize + chunks * Int64(tagLength)
    }

    static func nonce(_ index: UInt64, final: Bool, domain: UInt8 = 0) throws -> ChaChaPoly.Nonce {
        var bytes = Data([domain, final ? 1 : 0, 0, 0])
        bytes.append(index.bigEndianData)
        return try ChaChaPoly.Nonce(data: bytes)
    }

    /// Seals small metadata (the ``FileOffer``) with the file's key, in its own nonce space.
    public static func seal(_ metadata: Data, key: SymmetricKey) throws -> Data {
        try ChaChaPoly.seal(metadata, using: key, nonce: nonce(0, final: true, domain: 0xA5)).combined
    }

    public static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        let box = try ChaChaPoly.SealedBox(combined: sealed)
        guard Data(box.nonce) == Data(try nonce(0, final: true, domain: 0xA5)) else { throw Failure.damaged }
        return try ChaChaPoly.open(box, using: key)
    }

    // MARK: - Streaming

    /// Seals a file chunk by chunk, as it's read.
    public struct Encryptor: Sendable {
        private let key: SymmetricKey
        private var index: UInt64 = 0

        public init(key: SymmetricKey) {
            self.key = key
        }

        public mutating func seal(_ chunk: Data, isFinal: Bool) throws -> Data {
            let box = try ChaChaPoly.seal(chunk, using: key, nonce: nonce(index, final: isFinal))
            index += 1
            return box.ciphertext + box.tag
        }
    }

    /// Opens an encrypted stream as it arrives, in whatever pieces the network delivers. Call ``finish()`` at the
    /// end: that's when the last chunk is opened, and when a cut-short file is caught.
    public struct Decryptor: Sendable {
        private let key: SymmetricKey
        private var index: UInt64 = 0
        private var buffer = Data()
        private var finished = false

        public init(key: SymmetricKey) {
            self.key = key
        }

        static let sealedChunk = chunkSize + tagLength

        /// Takes in bytes and returns whatever plaintext is ready. The last chunk is held back until ``finish()``,
        /// since only then do we know it's the last.
        public mutating func update(_ bytes: Data) throws -> Data {
            buffer.append(bytes)
            var plain = Data()
            while buffer.count > Self.sealedChunk {
                plain.append(try open(buffer.prefix(Self.sealedChunk), isFinal: false))
                buffer.removeFirst(Self.sealedChunk)
            }
            return plain
        }

        public mutating func finish() throws -> Data {
            guard !finished else { throw Failure.damaged }
            finished = true
            guard buffer.count >= tagLength else { throw Failure.truncated }
            do {
                return try open(buffer, isFinal: true)
            } catch {
                // A whole chunk that isn't marked final means the rest of the file is missing.
                throw buffer.count == Self.sealedChunk ? Failure.truncated : Failure.damaged
            }
        }

        private mutating func open(_ sealed: Data, isFinal: Bool) throws -> Data {
            let sealed = Data(sealed)
            let split = sealed.count - tagLength
            let box = try ChaChaPoly.SealedBox(nonce: nonce(index, final: isFinal),
                                               ciphertext: sealed.prefix(split), tag: sealed.suffix(tagLength))
            guard let plain = try? ChaChaPoly.open(box, using: key) else { throw Failure.damaged }
            index += 1
            return plain
        }
    }

    // MARK: - Whole files

    /// Encrypts `source` into `destination`.
    public static func encryptFile(at source: URL, to destination: URL, key: SymmetricKey) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: destination.path(percentEncoded: false), contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var encryptor = Encryptor(key: key)
        var chunk = try input.read(upToCount: chunkSize) ?? Data()
        while true {
            let next = chunk.count == chunkSize ? (try input.read(upToCount: chunkSize) ?? Data()) : Data()
            let isFinal = next.isEmpty
            try output.write(contentsOf: encryptor.seal(chunk, isFinal: isFinal))
            if isFinal { break }
            chunk = next
        }
    }

    /// Decrypts `source` into `destination`, failing (and leaving nothing behind) if anything was changed or cut.
    public static func decryptFile(at source: URL, to destination: URL, key: SymmetricKey) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: destination.path(percentEncoded: false), contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        var decryptor = Decryptor(key: key)
        do {
            while let bytes = try input.read(upToCount: Decryptor.sealedChunk), !bytes.isEmpty {
                try output.write(contentsOf: decryptor.update(bytes))
            }
            try output.write(contentsOf: decryptor.finish())
            try output.close()
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
