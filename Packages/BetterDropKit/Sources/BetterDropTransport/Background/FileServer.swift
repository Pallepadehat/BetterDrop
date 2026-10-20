import BetterDropCore
import CryptoKit
import Foundation
import Network
import Synchronization

/// What happens on the ``FileServer``.
public enum FileServerEvent: Sendable {
    case incomingStarted(FileOffer, from: DeviceID)
    case progress(UUID, completed: Int64)
    /// A file arrived whole and checked, in a temporary folder: move it somewhere to keep it.
    case received(FileOffer, URL, from: DeviceID)
    /// A phone finished fetching a file we offered.
    case sent(UUID)
    case failed(UUID, reason: String)
}

/// The Mac's side of background transfers: a tiny HTTP server for big files (see ``BackgroundProtocol``).
///
/// It streams: an upload is decrypted and written as it arrives, a download is read and encrypted as it goes, so
/// a 20 GB video never has to fit in memory or exist twice on disk.
public final class FileServer: Sendable {
    public let events: AsyncStream<FileServerEvent>
    private let continuation: AsyncStream<FileServerEvent>.Continuation
    private let listener: NWListener
    private let store: any PairingStore
    private let inbox: URL
    private let offered = Mutex<[String: Offered]>([:])
    private let ready = Mutex<UInt16?>(nil)

    private struct Offered: Sendable {
        let file: URL
        let offer: FileOffer
        let key: SymmetricKey
        let device: DeviceID
        let expires: Date
    }

    public init(store: any PairingStore, inbox: URL = Link.defaultInbox, port: NWEndpoint.Port = .any) throws {
        self.store = store
        self.inbox = inbox
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        listener = try NWListener(using: NWParameters(tls: nil, tcp: tcp), on: port)
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// Starts listening and returns the port.
    public func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            let framed = FramedConnection(connection)
            Task { await self.serve(framed) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let port = self?.listener.port?.rawValue ?? 0
                    self?.ready.withLock { $0 = port }
                    if resumed.withLock({ was in defer { was = true }; return !was }) { continuation.resume(returning: port) }
                case let .failed(error):
                    if resumed.withLock({ was in defer { was = true }; return !was }) { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue(label: "BetterDrop.files"))
        }
    }

    public func stop() {
        listener.cancel()
        continuation.finish()
    }

    public var port: UInt16? { ready.withLock { $0 } }

    /// Makes a file available for one paired phone to fetch, and returns what to tell it.
    public func offer(fileAt url: URL, as offer: FileOffer, to pairing: PairedDevice) -> BackgroundOffer {
        let token = FileCipher.makeSalt().base64URL
        let salt = FileCipher.makeSalt()
        let entry = Offered(file: url, offer: offer, key: FileCipher.key(secret: pairing.secret, salt: salt),
                            device: pairing.id, expires: .now.addingTimeInterval(6 * 60 * 60))
        offered.withLock { offers in
            offers = offers.filter { $0.value.expires > .now }
            offers[token] = entry
        }
        return BackgroundOffer(offer: offer, token: token, salt: salt)
    }

    public func withdraw(_ id: UUID) {
        offered.withLock { offers in offers = offers.filter { $0.value.offer.id != id } }
    }

    // MARK: - HTTP

    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        /// Body bytes that arrived with the head.
        let leftover: Data

        var contentLength: Int64? { headers["content-length"].flatMap(Int64.init) }
    }

    private func serve(_ connection: FramedConnection) async {
        connection.connection.start(queue: DispatchQueue(label: "BetterDrop.files.connection"))
        defer { connection.cancel() }
        guard let request = try? await readHead(connection) else { return }
        do {
            switch (request.method, request.path) {
            case ("PUT", BackgroundProtocol.uploadPath):
                try await receiveUpload(request, over: connection)
            case ("GET", let path) where path.hasPrefix(BackgroundProtocol.downloadPrefix):
                try await serveDownload(token: String(path.dropFirst(BackgroundProtocol.downloadPrefix.count)), request, over: connection)
            default:
                try await respond(404, over: connection)
            }
        } catch let status as Status {
            try? await respond(status.code, over: connection)
        } catch {
            try? await respond(500, over: connection)
        }
    }

    private struct Status: Error {
        let code: Int
    }

    private func readHead(_ connection: FramedConnection) async throws -> Request {
        var buffer = Data()
        let end = Data("\r\n\r\n".utf8)
        while buffer.range(of: end) == nil {
            guard buffer.count < 32 * 1024, let more = try await connection.receiveSome(maximum: 16 * 1024) else { throw Status(code: 400) }
            buffer.append(more)
        }
        let split = buffer.range(of: end)!
        guard let head = String(data: buffer[..<split.lowerBound], encoding: .utf8) else { throw Status(code: 400) }
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { throw Status(code: 400) }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return Request(method: String(parts[0]), path: String(parts[1]), headers: headers, leftover: Data(buffer[split.upperBound...]))
    }

    private func respond(_ code: Int, headers: [String: String] = [:], over connection: FramedConnection) async throws {
        let reason = [200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 500: "Internal Server Error"][code] ?? "Status"
        var head = "HTTP/1.1 \(code) \(reason)\r\n"
        var all = headers
        if all["Content-Length"] == nil { all["Content-Length"] = "0" }
        all["Connection"] = "close"
        for (name, value) in all { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        try await connection.sendRaw(Data(head.utf8))
    }

    // MARK: Uploads

    private func receiveUpload(_ request: Request, over connection: FramedConnection) async throws {
        guard let deviceID = request.headers[BackgroundProtocol.deviceHeader].map(DeviceID.init(rawValue:)),
              let pairing = store.pairing(for: deviceID),
              let salt = request.headers[BackgroundProtocol.saltHeader].flatMap(Data.init(base64URL:)),
              let sealed = request.headers[BackgroundProtocol.offerHeader].flatMap(Data.init(base64URL:))
        else { throw Status(code: 401) }
        let key = FileCipher.key(secret: pairing.secret, salt: salt)
        // Opening the offer is the proof: only a paired phone could have sealed it.
        guard let json = try? FileCipher.open(sealed, key: key),
              let offer = try? JSONDecoder().decode(FileOffer.self, from: json)
        else { throw Status(code: 401) }
        guard let length = request.contentLength, length == FileCipher.encryptedSize(of: offer.byteCount) else { throw Status(code: 400) }

        let folder = inbox.appending(path: offer.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: FileNames.sanitized(offer.name))
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        let output = try FileHandle(forWritingTo: url)
        continuation.yield(.incomingStarted(offer, from: deviceID))

        var decryptor = FileCipher.Decryptor(key: key)
        var received: Int64 = 0
        var written: Int64 = 0
        func take(_ bytes: Data) throws {
            received += Int64(bytes.count)
            let plain = try decryptor.update(bytes)
            try output.write(contentsOf: plain)
            written += Int64(plain.count)
            continuation.yield(.progress(offer.id, completed: min(offer.byteCount, received * offer.byteCount / max(1, length))))
        }
        do {
            if !request.leftover.isEmpty { try take(request.leftover) }
            while received < length {
                guard let bytes = try await connection.receiveSome(maximum: Int(min(length - received, 1 << 20))) else {
                    throw FileCipher.Failure.truncated
                }
                try take(bytes)
            }
            let last = try decryptor.finish()
            try output.write(contentsOf: last)
            written += Int64(last.count)
            try output.close()
            guard written == offer.byteCount else { throw FileCipher.Failure.damaged }
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: folder)
            continuation.yield(.failed(offer.id, reason: String(localized: "The file didn't arrive intact.")))
            throw Status(code: 400)
        }
        try await respond(201, over: connection)
        continuation.yield(.received(offer, url, from: deviceID))
    }

    // MARK: Downloads

    private func serveDownload(token: String, _ request: Request, over connection: FramedConnection) async throws {
        guard let entry = offered.withLock({ $0[token] }), entry.expires > .now,
              request.headers[BackgroundProtocol.deviceHeader] == entry.device.rawValue
        else { throw Status(code: 404) }
        let input = try FileHandle(forReadingFrom: entry.file)
        defer { try? input.close() }
        try await respond(200, headers: ["Content-Length": String(FileCipher.encryptedSize(of: entry.offer.byteCount)),
                                         "Content-Type": "application/octet-stream"], over: connection)
        var encryptor = FileCipher.Encryptor(key: entry.key)
        var sent: Int64 = 0
        var chunk = try input.read(upToCount: FileCipher.chunkSize) ?? Data()
        do {
            while true {
                let next = chunk.count == FileCipher.chunkSize ? (try input.read(upToCount: FileCipher.chunkSize) ?? Data()) : Data()
                try await connection.sendRaw(encryptor.seal(chunk, isFinal: next.isEmpty))
                sent += Int64(chunk.count)
                continuation.yield(.progress(entry.offer.id, completed: sent))
                if next.isEmpty { break }
                chunk = next
            }
        } catch {
            // The phone went away; iOS will try again, and the token is still good.
            return
        }
        offered.withLock { _ = $0.removeValue(forKey: token) }
        continuation.yield(.sent(entry.offer.id))
    }
}
