import BetterDropCore
import CryptoKit
import Foundation
import Network
import Testing
@testable import BetterDropTransport

/// The phone and the Mac in one process, talking over localhost: pairing, a session and real file transfers.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LoopbackTests {
    let phone = DeviceInfo(id: .random(), name: "Patrick's iPhone", kind: .iPhone)
    let mac = DeviceInfo(id: .random(), name: "Patrick's MacBook Pro", kind: .mac)
    let macStore = MemoryPairingStore()

    /// Starts a listener on localhost that accepts every phone (or none), and returns its port and the Mac's links.
    private func startMac(approve: Bool = true) async throws -> (DeviceAdvertiser, NWEndpoint.Port, AsyncStream<Link>) {
        let (links, linksContinuation) = AsyncStream.makeStream(of: Link.self)
        let mac = mac, store = macStore
        let advertiser = DeviceAdvertiser(device: mac, advertises: false) { connection in
            Task {
                // Declined and forgotten phones end here, which is what those tests expect.
                guard (try? await connection.start()) != nil,
                      let (channel, peer) = try? await ServerHandshake.accept(connection, as: mac, store: store, approve: { _ in approve })
                else { return }
                let link = Link(channel: channel, peer: peer, inbox: FileManager.default.temporaryDirectory.appending(path: "mac-inbox-\(UUID())"))
                await link.start()
                linksContinuation.yield(link)
            }
        }
        advertiser.start()
        while true {
            if case let .advertising(port) = advertiser.state, port != 0 { return (advertiser, NWEndpoint.Port(rawValue: port)!, links) }
            if case let .failed(reason) = advertiser.state { Issue.record("Listener failed: \(reason)"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func connect(_ port: NWEndpoint.Port) async throws -> FramedConnection {
        let connection = FramedConnection(to: .hostPort(host: "127.0.0.1", port: port))
        try await connection.start()
        return connection
    }

    @Test func pairsThenSendsFilesBothWays() async throws {
        let (advertiser, port, macLinks) = try await startMac()
        defer { advertiser.stop() }

        // Pair, and see the code.
        let codes = AsyncStream.makeStream(of: String.self)
        let connection = try await connect(port)
        let pairing = try await ClientHandshake.pair(over: connection, as: phone) { codes.continuation.yield($0) }
        #expect(pairing.device == mac)
        #expect(macStore.pairing(for: phone.id) != nil)
        var codeIterator = codes.stream.makeAsyncIterator()
        #expect(await codeIterator.next()?.count == 6)

        let (channel, peer) = try await ClientHandshake.startSession(over: connection, as: phone, with: pairing)
        #expect(peer == mac)
        let phoneLink = Link(channel: channel, peer: peer, inbox: FileManager.default.temporaryDirectory.appending(path: "phone-inbox-\(UUID())"))
        await phoneLink.start()
        var macLinkIterator = macLinks.makeAsyncIterator()
        let macLink = try #require(await macLinkIterator.next())

        // Phone → Mac: three megabytes and a bit, so it takes several chunks and ends on a partial one.
        let bytes = Data((0..<(3 * 1024 * 1024 + 1234)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let source = FileManager.default.temporaryDirectory.appending(path: "Golden Hour-\(UUID()).jpg")
        try bytes.write(to: source)
        let offer = FileOffer(name: "../Golden Hour.jpg", byteCount: Int64(bytes.count), contentTypeIdentifier: "public.jpeg")

        async let sent: Void = phoneLink.send(fileAt: source, as: offer)
        var arrived: URL?
        var lastProgress: Int64 = 0
        for await event in macLink.events {
            if case let .progress(id, completed) = event, id == offer.id { lastProgress = completed }
            if case let .incomingFinished(received, url) = event {
                #expect(received.id == offer.id)
                arrived = url
                break
            }
        }
        try await sent
        let url = try #require(arrived)
        #expect(url.lastPathComponent == "Golden Hour.jpg")
        #expect(try Data(contentsOf: url) == bytes)
        #expect(lastProgress == Int64(bytes.count))

        // Mac → phone, an empty file.
        let empty = FileManager.default.temporaryDirectory.appending(path: "empty-\(UUID()).txt")
        try Data().write(to: empty)
        let emptyOffer = FileOffer(name: "empty.txt", byteCount: 0, contentTypeIdentifier: "public.plain-text")
        async let sentBack: Void = macLink.send(fileAt: empty, as: emptyOffer)
        for await event in phoneLink.events {
            if case let .incomingFinished(received, url) = event {
                #expect(received.name == "empty.txt")
                #expect(try Data(contentsOf: url).isEmpty)
                break
            }
        }
        try await sentBack

        // Small messages arrive too.
        try await phoneLink.send(.proximity(.touching))
        for await event in macLink.events {
            if case let .proximity(proximity) = event { #expect(proximity == .touching); break }
        }

        // And when the phone goes away, the Mac hears about it.
        await phoneLink.close()
        var closed = false
        for await event in macLink.events { if case .closed = event { closed = true } }
        #expect(closed)
    }

    @Test func aPairedPhoneReconnectsWithoutAsking() async throws {
        let (advertiser, port, macLinks) = try await startMac()
        defer { advertiser.stop() }
        let pairing = try await ClientHandshake.pair(over: try await connect(port), as: phone) { _ in }

        let (_, peer) = try await ClientHandshake.startSession(over: try await connect(port), as: phone, with: pairing)
        #expect(peer == mac)
        var links = macLinks.makeAsyncIterator()
        #expect(await links.next()?.peer == phone)
    }

    @Test func aDeclinedPhoneIsTold() async throws {
        let (advertiser, port, _) = try await startMac(approve: false)
        defer { advertiser.stop() }
        await #expect(throws: HandshakeError.rejected(.declined)) {
            try await ClientHandshake.pair(over: try await connect(port), as: phone) { _ in }
        }
        #expect(macStore.all().isEmpty)
    }

    @Test func aForgottenPhoneMustPairAgain() async throws {
        let (advertiser, port, _) = try await startMac()
        defer { advertiser.stop() }
        let pairing = try await ClientHandshake.pair(over: try await connect(port), as: phone) { _ in }
        try macStore.remove(phone.id)
        await #expect(throws: HandshakeError.rejected(.unknownDevice)) {
            try await ClientHandshake.startSession(over: try await connect(port), as: phone, with: pairing)
        }
    }
}
