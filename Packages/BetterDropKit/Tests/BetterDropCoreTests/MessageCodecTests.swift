import Foundation
import Testing
@testable import BetterDropCore

struct MessageCodecTests {
    static let id = UUID()

    @Test(arguments: [
        Message.offer(FileOffer(id: id, name: "Golden Hour.jpg", byteCount: 367_000, contentTypeIdentifier: "public.jpeg", aspectRatio: 1.5)),
        .accept(id),
        .decline(id, reason: "No room"),
        .chunk(id, offset: 0, Data()),
        .chunk(id, offset: 1 << 40, Data((0..<255).map { UInt8($0) })),
        .complete(id, sha256: Data(repeating: 0xAB, count: 32)),
        .received(id),
        .cancel(id),
        .proximity(.touching),
        .closeness(0.75),
        .side(.left),
        .fileServer(FileServerAddress(port: 51234, hosts: ["192.168.1.20"])),
        .backgroundOffer(BackgroundOffer(offer: FileOffer(id: id, name: "Trip.mov", byteCount: 4_000_000_000, contentTypeIdentifier: "com.apple.quicktime-movie"),
                                         token: "abc", salt: Data(repeating: 3, count: 32))),
        .rename("Patrick's MacBook Pro"),
        .ping,
        .pong,
    ])
    func roundTrips(_ message: Message) throws {
        #expect(try MessageCodec.decode(MessageCodec.encode(message)) == message)
    }

    @Test func chunksAreRawBytesNotJSON() throws {
        let payload = Data(repeating: 1, count: 1024)
        let encoded = try MessageCodec.encode(.chunk(Self.id, offset: 7, payload))
        #expect(encoded.count == MessageCodec.chunkHeaderLength + payload.count)
    }

    @Test func decodesFromSlices() throws {
        // Data that's a slice of a bigger buffer doesn't start at index 0.
        let encoded = Data([9, 9]) + (try MessageCodec.encode(.chunk(Self.id, offset: 42, Data([1, 2, 3]))))
        #expect(try MessageCodec.decode(encoded.dropFirst(2)) == .chunk(Self.id, offset: 42, Data([1, 2, 3])))
    }

    @Test func rejectsGarbage() {
        #expect(throws: MessageCodec.DecodingError.empty) { try MessageCodec.decode(Data()) }
        #expect(throws: MessageCodec.DecodingError.unknownTag(0x7F)) { try MessageCodec.decode(Data([0x7F])) }
        #expect(throws: MessageCodec.DecodingError.truncatedChunk) { try MessageCodec.decode(Data([0x02, 1, 2])) }
    }
}
