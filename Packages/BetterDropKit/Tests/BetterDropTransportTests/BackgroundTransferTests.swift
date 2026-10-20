import BetterDropCore
import Foundation
import Testing
@testable import BetterDropTransport

/// The file server and the URLSession client in one process, over localhost.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct BackgroundTransferTests {
    let phone = DeviceInfo(id: .random(), name: "Patrick's iPhone", kind: .iPhone)
    let mac = DeviceInfo(id: .random(), name: "Patrick's MacBook Pro", kind: .mac)
    let secret = Data((0..<32).map { UInt8($0) })

    private func temporary(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "bg-\(UUID().uuidString)/\(name)")
    }

    private func makeFile(size: Int) throws -> (URL, Data) {
        let bytes = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 13) })
        let url = temporary("Trip.mov")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        return (url, bytes)
    }

    @Test func uploadsAndDownloadsEncryptedFiles() async throws {
        let macStore = MemoryPairingStore([PairedDevice(device: phone, secret: secret)])
        let phoneStore = MemoryPairingStore([PairedDevice(device: mac, secret: secret)])
        let server = try FileServer(store: macStore, inbox: temporary("mac-inbox"))
        let port = try await server.start()
        defer { server.stop() }
        let base = try #require(BackgroundProtocol.baseURL(for: FileServerAddress(port: port, hosts: ["127.0.0.1"]), preferring: nil))
        let client = BackgroundTransfers(identifier: nil, store: phoneStore, outbox: temporary("outbox"), inbox: temporary("phone-inbox"))

        // Phone → Mac, a bit over two chunks.
        let (source, bytes) = try makeFile(size: FileCipher.chunkSize * 2 + 4321)
        let offer = FileOffer(name: "Trip.mov", byteCount: Int64(bytes.count), contentTypeIdentifier: "com.apple.quicktime-movie")
        try await client.upload(fileAt: source, as: offer, pairing: phoneStore.pairing(for: mac.id)!, from: phone.id, to: base)

        var arrived: URL?
        for await event in server.events {
            if case let .received(received, url, from) = event {
                #expect(received == offer)
                #expect(from == phone.id)
                arrived = url
                break
            }
            if case let .failed(_, reason) = event { Issue.record("Upload failed: \(reason)"); break }
        }
        #expect(try Data(contentsOf: #require(arrived)) == bytes)
        for await event in client.events {
            if case let .uploaded(id) = event { #expect(id == offer.id); break }
            if case let .failed(_, reason) = event { Issue.record("Client says: \(reason)"); break }
        }

        // Mac → phone.
        let (other, otherBytes) = try makeFile(size: FileCipher.chunkSize + 1)
        let otherOffer = FileOffer(name: "Walrus.mov", byteCount: Int64(otherBytes.count), contentTypeIdentifier: "com.apple.quicktime-movie")
        let offered = server.offer(fileAt: other, as: otherOffer, to: macStore.pairing(for: phone.id)!)
        client.download(offered, pairing: phoneStore.pairing(for: mac.id)!, as: phone.id, from: base)
        var downloaded: URL?
        for await event in client.events {
            if case let .downloaded(received, url, from) = event {
                #expect(received == otherOffer)
                #expect(from == mac.id)
                downloaded = url
                break
            }
            if case let .failed(_, reason) = event { Issue.record("Download failed: \(reason)"); break }
        }
        let url = try #require(downloaded)
        #expect(url.lastPathComponent == "Walrus.mov")
        #expect(try Data(contentsOf: url) == otherBytes)
    }

    @Test func turnsAwayStrangers() async throws {
        let server = try FileServer(store: MemoryPairingStore([PairedDevice(device: phone, secret: secret)]), inbox: temporary("inbox"))
        let port = try await server.start()
        defer { server.stop() }
        let base = try #require(BackgroundProtocol.baseURL(for: FileServerAddress(port: port, hosts: ["127.0.0.1"]), preferring: nil))
        // Knows the phone's ID, but not its secret.
        let strangerStore = MemoryPairingStore([PairedDevice(device: mac, secret: Data(repeating: 7, count: 32))])
        let client = BackgroundTransfers(identifier: nil, store: strangerStore, outbox: temporary("outbox"), inbox: temporary("phone-inbox"))
        let (source, bytes) = try makeFile(size: 1000)
        let offer = FileOffer(name: "x.bin", byteCount: Int64(bytes.count), contentTypeIdentifier: "public.data")
        try await client.upload(fileAt: source, as: offer, pairing: strangerStore.pairing(for: mac.id)!, from: phone.id, to: base)
        for await event in client.events {
            if case .uploaded = event { Issue.record("A stranger got a file in"); break }
            if case .failed = event { break }
        }

        // And can't fetch something offered to someone else.
        let offered = server.offer(fileAt: source, as: offer, to: PairedDevice(device: phone, secret: secret))
        var request = URLRequest(url: base.appending(path: "v1/files/\(offered.token)"))
        request.setValue(DeviceID.random().rawValue, forHTTPHeaderField: "X-BetterDrop-Device")
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 404)
    }

    @Test func prefersAnAddressBackgroundDownloadsCanReach() {
        let address = FileServerAddress(port: 8000, hosts: ["192.168.1.20", "10.0.0.5"])
        #expect(BackgroundProtocol.baseURL(for: address, preferring: "fe80::1%en0")?.absoluteString == "http://192.168.1.20:8000")
        #expect(BackgroundProtocol.baseURL(for: address, preferring: "192.168.1.99")?.absoluteString == "http://192.168.1.99:8000")
        #expect(BackgroundProtocol.baseURL(for: FileServerAddress(port: 1, hosts: []), preferring: nil) == nil)
        #expect(BackgroundProtocol.shouldUseBackground(for: 100 * 1024 * 1024))
        #expect(!BackgroundProtocol.shouldUseBackground(for: 1024))
    }
}
