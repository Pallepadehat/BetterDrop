import Foundation

/// Turns ``Message``s into bytes and back.
///
/// The first byte says what follows. Chunks are raw bytes behind a fixed header, so a gigabyte video isn't base64'd
/// through JSON; everything else is small and JSON keeps it easy to evolve.
///
///     chunk:    0x02 | id (16 bytes) | offset (UInt64, big-endian) | data
///     control:  0x01 | JSON
public enum MessageCodec {
    public enum DecodingError: Error, Equatable {
        case empty
        case unknownTag(UInt8)
        case truncatedChunk
    }

    private enum Tag: UInt8 {
        case control = 0x01
        case chunk = 0x02
    }

    /// The JSON half: every message except chunks.
    private enum Control: Codable {
        case offer(FileOffer)
        case accept(UUID)
        case decline(UUID, reason: String)
        case complete(UUID, sha256: Data)
        case received(UUID)
        case cancel(UUID)
        case proximity(Proximity)
        case rename(String)
        case ping
        case pong
    }

    static let chunkHeaderLength = 1 + 16 + 8

    public static func encode(_ message: Message) throws -> Data {
        let control: Control
        switch message {
        case let .chunk(id, offset, bytes):
            var data = Data(capacity: chunkHeaderLength + bytes.count)
            data.append(Tag.chunk.rawValue)
            data.append(id.data)
            data.append(offset.bigEndianData)
            data.append(bytes)
            return data
        case let .offer(offer): control = .offer(offer)
        case let .accept(id): control = .accept(id)
        case let .decline(id, reason): control = .decline(id, reason: reason)
        case let .complete(id, digest): control = .complete(id, sha256: digest)
        case let .received(id): control = .received(id)
        case let .cancel(id): control = .cancel(id)
        case let .proximity(proximity): control = .proximity(proximity)
        case let .rename(name): control = .rename(name)
        case .ping: control = .ping
        case .pong: control = .pong
        }
        var data = Data([Tag.control.rawValue])
        data.append(try JSONEncoder().encode(control))
        return data
    }

    public static func decode(_ data: Data) throws -> Message {
        guard let first = data.first else { throw DecodingError.empty }
        guard let tag = Tag(rawValue: first) else { throw DecodingError.unknownTag(first) }
        let body = data.dropFirst()
        switch tag {
        case .chunk:
            guard data.count >= chunkHeaderLength else { throw DecodingError.truncatedChunk }
            let start = body.startIndex
            let id = UUID(data: body[start..<start + 16])
            let offset = UInt64(bigEndianData: body[start + 16..<start + 24])
            return .chunk(id, offset: offset, Data(body[(start + 24)...]))
        case .control:
            return switch try JSONDecoder().decode(Control.self, from: body) {
            case let .offer(offer): .offer(offer)
            case let .accept(id): .accept(id)
            case let .decline(id, reason): .decline(id, reason: reason)
            case let .complete(id, digest): .complete(id, sha256: digest)
            case let .received(id): .received(id)
            case let .cancel(id): .cancel(id)
            case let .proximity(proximity): .proximity(proximity)
            case let .rename(name): .rename(name)
            case .ping: .ping
            case .pong: .pong
            }
        }
    }
}

extension UUID {
    var data: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }

    init(data: some Collection<UInt8>) {
        var bytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &bytes) { buffer in
            for (index, byte) in zip(buffer.indices, data) { buffer[index] = byte }
        }
        self.init(uuid: bytes)
    }
}

extension FixedWidthInteger {
    var bigEndianData: Data {
        withUnsafeBytes(of: bigEndian) { Data($0) }
    }

    init(bigEndianData data: some Collection<UInt8>) {
        self = data.reduce(0) { ($0 << 8) | Self($1) }
    }
}
