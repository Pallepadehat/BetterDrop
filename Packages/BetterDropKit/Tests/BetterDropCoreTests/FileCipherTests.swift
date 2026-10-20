import CryptoKit
import Foundation
import Testing
@testable import BetterDropCore

struct FileCipherTests {
    let key = FileCipher.key(secret: Data(repeating: 9, count: 32), salt: FileCipher.makeSalt())

    private func temporary(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
    }

    @Test(arguments: [0, 1, FileCipher.chunkSize - 1, FileCipher.chunkSize, FileCipher.chunkSize + 1, FileCipher.chunkSize * 3 + 777])
    func roundTripsFilesOfAnySize(size: Int) throws {
        let plain = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        let source = temporary("plain"), sealed = temporary("sealed"), opened = temporary("opened")
        defer { for url in [source, sealed, opened] { try? FileManager.default.removeItem(at: url) } }
        try plain.write(to: source)

        try FileCipher.encryptFile(at: source, to: sealed, key: key)
        let sealedSize = try FileManager.default.attributesOfItem(atPath: sealed.path(percentEncoded: false))[.size] as? Int64
        #expect(sealedSize == FileCipher.encryptedSize(of: Int64(size)))

        try FileCipher.decryptFile(at: sealed, to: opened, key: key)
        #expect(try Data(contentsOf: opened) == plain)
    }

    @Test func streamsInOddPieces() throws {
        let plain = Data((0..<(FileCipher.chunkSize * 2 + 5)).map { UInt8(truncatingIfNeeded: $0) })
        var encryptor = FileCipher.Encryptor(key: key)
        var sealed = Data()
        var offset = 0
        while offset < plain.count {
            let end = min(plain.count, offset + FileCipher.chunkSize)
            sealed.append(try encryptor.seal(plain[offset..<end], isFinal: end == plain.count))
            offset = end
        }
        var decryptor = FileCipher.Decryptor(key: key)
        var opened = Data()
        var cursor = sealed.startIndex
        while cursor < sealed.endIndex {
            let end = min(sealed.endIndex, cursor + 77_777)
            opened.append(try decryptor.update(sealed[cursor..<end]))
            cursor = end
        }
        opened.append(try decryptor.finish())
        #expect(opened == plain)
    }

    @Test func catchesTruncationTamperingAndTheWrongKey() throws {
        let plain = Data(repeating: 1, count: FileCipher.chunkSize * 2 + 10)
        var encryptor = FileCipher.Encryptor(key: key)
        let first = try encryptor.seal(plain.prefix(FileCipher.chunkSize), isFinal: false)

        var cut = FileCipher.Decryptor(key: key)
        _ = try cut.update(first)
        #expect(throws: FileCipher.Failure.truncated) { try cut.finish() }

        var flipped = first
        flipped[flipped.startIndex + 10] ^= 0xFF
        var tampered = FileCipher.Decryptor(key: key)
        #expect(throws: FileCipher.Failure.damaged) { _ = try tampered.update(flipped + Data(repeating: 0, count: 100)) }

        var stranger = FileCipher.Decryptor(key: SymmetricKey(size: .bits256))
        #expect(throws: (any Error).self) { _ = try stranger.update(first + Data(repeating: 0, count: 20)) }
    }

    @Test func sealsMetadataSeparately() throws {
        let offer = Data("{\"name\":\"walrus.mov\"}".utf8)
        let sealed = try FileCipher.seal(offer, key: key)
        #expect(try FileCipher.open(sealed, key: key) == offer)
        #expect(throws: (any Error).self) { try FileCipher.open(sealed, key: SymmetricKey(size: .bits256)) }
    }
}
