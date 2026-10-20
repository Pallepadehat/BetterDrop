import BetterDropCore
import CryptoKit
import Foundation

/// What happens on a ``Link``, in order.
public enum LinkEvent: Sendable {
    /// The other side started sending us a file.
    case incomingStarted(FileOffer)
    /// Bytes moved, either way.
    case progress(UUID, completed: Int64)
    /// A file arrived whole and checked. It's in a temporary folder: move it somewhere to keep it.
    case incomingFinished(FileOffer, URL)
    /// The other side has the file we sent, checked and saved.
    case outgoingFinished(UUID)
    case failed(UUID, reason: String)
    case proximity(Proximity)
    case renamed(String)
    /// The connection is gone. Every transfer still going has been reported as failed.
    case closed
}

/// A live, encrypted connection to a paired device, moving files both ways.
///
/// Files go in 256 KB chunks, in order, each one handed to the network before the next is read, so sending a huge
/// video doesn't fill memory. The receiver hashes as it writes and checks the SHA-256 at the end; a file only shows
/// up in ``LinkEvent/incomingFinished(_:_:)`` once it's whole and matches.
public actor Link {
    public nonisolated let peer: DeviceInfo
    public nonisolated let events: AsyncStream<LinkEvent>

    static let chunkSize = 256 * 1024

    private let channel: SecureChannel
    private let continuation: AsyncStream<LinkEvent>.Continuation
    private let inbox: URL
    private var incoming: [UUID: IncomingFile] = [:]
    /// Files we're sending, and the answers we're waiting on for them.
    private var outgoing: Set<UUID> = []
    private var acceptances = Waiters()
    private var receipts = Waiters()
    private var cancelledOutgoing: Set<UUID> = []
    private var receiving: Task<Void, Never>?
    private var isClosed = false

    public enum Failure: Error, LocalizedError, Equatable {
        case declined(String)
        case cancelled
        case closed
        case corrupted

        public var errorDescription: String? {
            switch self {
            case let .declined(reason): reason
            case .cancelled: String(localized: "The transfer was cancelled.")
            case .closed: String(localized: "The connection was lost.")
            case .corrupted: String(localized: "The file didn't arrive intact.")
            }
        }
    }

    public init(channel: SecureChannel, peer: DeviceInfo, inbox: URL = Link.defaultInbox) {
        self.channel = channel
        self.peer = peer
        self.inbox = inbox
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// Where files are written while they arrive. Anything left here from an earlier run is unfinished.
    public static var defaultInbox: URL {
        FileManager.default.temporaryDirectory.appending(path: "BetterDrop Inbox", directoryHint: .isDirectory)
    }

    public static func clearInbox(_ inbox: URL = defaultInbox) {
        try? FileManager.default.removeItem(at: inbox)
    }

    /// Starts listening. Call once.
    public func start() {
        guard receiving == nil else { return }
        receiving = Task { await receiveLoop() }
    }

    public func close() {
        channel.close()
        shutDown()
    }

    /// Closes without waiting, from anywhere.
    public nonisolated func closeSoon() {
        Task { await close() }
    }

    // MARK: - Sending

    /// Sends a file and returns once the other side has it, checked and saved.
    public func send(fileAt url: URL, as offer: FileOffer) async throws {
        guard !isClosed else { throw Failure.closed }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        outgoing.insert(offer.id)
        defer {
            outgoing.remove(offer.id)
            cancelledOutgoing.remove(offer.id)
            acceptances.forget(offer.id)
            receipts.forget(offer.id)
        }
        try await channel.send(.offer(offer))
        try await withCheckedThrowingContinuation { acceptances.wait(for: offer.id, $0) }

        var hasher = SHA256()
        var offset: Int64 = 0
        do {
            while let data = try handle.read(upToCount: Self.chunkSize), !data.isEmpty {
                if cancelledOutgoing.contains(offer.id) || Task.isCancelled { throw Failure.cancelled }
                hasher.update(data: data)
                try await channel.send(.chunk(offer.id, offset: UInt64(offset), data))
                offset += Int64(data.count)
                continuation.yield(.progress(offer.id, completed: offset))
            }
            try await channel.send(.complete(offer.id, sha256: Data(hasher.finalize())))
        } catch {
            try? await channel.send(.cancel(offer.id))
            throw error
        }
        try await withCheckedThrowingContinuation { receipts.wait(for: offer.id, $0) }
        continuation.yield(.outgoingFinished(offer.id))
    }

    /// Stops a transfer either way.
    public func cancel(_ id: UUID) async {
        if incoming[id] != nil {
            discardIncoming(id, reason: Failure.cancelled.localizedDescription)
        } else if outgoing.contains(id) {
            cancelOutgoing(id)
        }
        try? await channel.send(.cancel(id))
    }

    /// For small things: proximity, a new name.
    public func send(_ message: Message) async throws {
        try await channel.send(message)
    }

    // MARK: - Receiving

    private func receiveLoop() async {
        while !Task.isCancelled {
            do {
                try await handle(channel.receive())
            } catch {
                break
            }
        }
        shutDown()
    }

    private func handle(_ message: Message) async throws {
        switch message {
        case let .offer(offer):
            try await receive(offer)
        case let .chunk(id, offset, data):
            guard var file = incoming[id] else { return }
            guard offset == UInt64(file.written), file.written + Int64(data.count) <= file.offer.byteCount else {
                discardIncoming(id, reason: Failure.corrupted.localizedDescription)
                try await channel.send(.cancel(id))
                return
            }
            try file.append(data)
            incoming[id] = file
            continuation.yield(.progress(id, completed: file.written))
        case let .complete(id, digest):
            guard var file = incoming.removeValue(forKey: id) else { return }
            guard file.finish(expecting: digest) else {
                file.discard()
                continuation.yield(.failed(id, reason: Failure.corrupted.localizedDescription))
                try await channel.send(.cancel(id))
                return
            }
            try await channel.send(.received(id))
            continuation.yield(.incomingFinished(file.offer, file.url))
        case let .accept(id) where outgoing.contains(id):
            acceptances.resolve(id, .success(()))
        case let .decline(id, reason) where outgoing.contains(id):
            acceptances.resolve(id, .failure(Failure.declined(reason)))
        case let .received(id) where outgoing.contains(id):
            receipts.resolve(id, .success(()))
        case .accept, .decline, .received:
            break
        case let .cancel(id):
            if incoming[id] != nil {
                discardIncoming(id, reason: Failure.cancelled.localizedDescription)
            } else if outgoing.contains(id) {
                cancelOutgoing(id)
            }
        case let .proximity(proximity):
            continuation.yield(.proximity(proximity))
        case let .rename(name):
            continuation.yield(.renamed(name))
        case .ping:
            try await channel.send(.pong)
        case .pong:
            break
        }
    }

    private func receive(_ offer: FileOffer) async throws {
        guard offer.byteCount >= 0, incoming[offer.id] == nil else {
            try await channel.send(.decline(offer.id, reason: "Bad offer"))
            return
        }
        if let free = Self.freeSpace(), free < offer.byteCount {
            try await channel.send(.decline(offer.id, reason: String(localized: "\(peer.name) is out of space.")))
            return
        }
        do {
            incoming[offer.id] = try IncomingFile(offer: offer, inbox: inbox)
        } catch {
            try await channel.send(.decline(offer.id, reason: error.localizedDescription))
            return
        }
        continuation.yield(.incomingStarted(offer))
        try await channel.send(.accept(offer.id))
    }

    private func cancelOutgoing(_ id: UUID) {
        cancelledOutgoing.insert(id)
        acceptances.resolve(id, .failure(Failure.cancelled))
        receipts.resolve(id, .failure(Failure.cancelled))
    }

    private func discardIncoming(_ id: UUID, reason: String) {
        incoming.removeValue(forKey: id)?.discard()
        continuation.yield(.failed(id, reason: reason))
    }

    private func shutDown() {
        guard !isClosed else { return }
        isClosed = true
        receiving?.cancel()
        for id in incoming.keys { discardIncoming(id, reason: Failure.closed.localizedDescription) }
        for id in outgoing {
            acceptances.resolve(id, .failure(Failure.closed))
            receipts.resolve(id, .failure(Failure.closed))
        }
        continuation.yield(.closed)
        continuation.finish()
    }

    private static func freeSpace() -> Int64? {
        try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }
}

/// Answers that may arrive before anyone is waiting for them (the network is quicker than the actor sometimes),
/// so an early answer is kept until it's asked for.
private struct Waiters {
    private var waiting: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var early: [UUID: Result<Void, any Error>] = [:]

    mutating func wait(for id: UUID, _ continuation: CheckedContinuation<Void, any Error>) {
        if let result = early.removeValue(forKey: id) {
            continuation.resume(with: result)
        } else {
            waiting[id] = continuation
        }
    }

    mutating func resolve(_ id: UUID, _ result: Result<Void, any Error>) {
        if let continuation = waiting.removeValue(forKey: id) {
            continuation.resume(with: result)
        } else if early[id] == nil {
            early[id] = result
        }
    }

    mutating func forget(_ id: UUID) {
        early.removeValue(forKey: id)
    }
}

/// A file on its way in: written to the inbox and hashed as the chunks arrive.
private struct IncomingFile {
    let offer: FileOffer
    let url: URL
    private let handle: FileHandle
    private var hasher = SHA256()
    private(set) var written: Int64 = 0

    init(offer: FileOffer, inbox: URL) throws {
        self.offer = offer
        // Its own folder, so the name can be the real one and nothing else in the inbox can clash.
        let folder = inbox.appending(path: offer.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: FileNames.sanitized(offer.name))
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
    }

    mutating func append(_ data: Data) throws {
        try handle.write(contentsOf: data)
        hasher.update(data: data)
        written += Int64(data.count)
    }

    mutating func finish(expecting digest: Data) -> Bool {
        try? handle.close()
        return written == offer.byteCount && Data(hasher.finalize()) == digest
    }

    func discard() {
        try? handle.close()
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
