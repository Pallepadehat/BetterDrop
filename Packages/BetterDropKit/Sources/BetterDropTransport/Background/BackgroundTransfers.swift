import BetterDropCore
import CryptoKit
import Foundation
import Synchronization

/// What happens to background transfers.
public enum BackgroundTransferEvent: Sendable {
    case progress(UUID, completed: Int64)
    /// A file we sent is on the Mac.
    case uploaded(UUID)
    /// A file the Mac offered is here, decrypted, in a temporary folder: move it somewhere to keep it.
    case downloaded(FileOffer, URL, from: DeviceID)
    case failed(UUID, reason: String)
}

/// The phone's side of big files: a background URLSession, so they keep going when you leave the app, lock the
/// phone or it's in your pocket. iOS runs the transfer itself and wakes the app when it's done.
///
/// Files are sealed with ``FileCipher`` before they go and opened when they arrive, so the HTTP only ever carries
/// ciphertext.
public final class BackgroundTransfers: NSObject, @unchecked Sendable {
    public let events: AsyncStream<BackgroundTransferEvent>
    private let continuation: AsyncStream<BackgroundTransferEvent>.Continuation
    private let store: any PairingStore
    private let outbox: URL
    private let inbox: URL
    private let completionHandler = Mutex<(@Sendable () -> Void)?>(nil)
    // Set once in init; URLSession keeps a strong reference to its delegate (us) until invalidated.
    private var session: URLSession!

    /// What we remember about a task, in its `taskDescription`, so it can be finished even if the app was killed
    /// and relaunched in the background meanwhile.
    private struct TaskInfo: Codable {
        enum Kind: String, Codable { case upload, download }
        var kind: Kind
        var offer: FileOffer
        var peer: DeviceID
        var salt: Data?
        var sealedFile: String?
    }

    /// `identifier` names the background session (the same every launch, so iOS hands back transfers it finished
    /// while we weren't running). Pass nil for an ordinary session, for tests.
    public init(identifier: String?, store: any PairingStore,
                outbox: URL = URL.cachesDirectory.appending(path: "BetterDrop Outbox", directoryHint: .isDirectory),
                inbox: URL = PeerLink.defaultInbox) {
        self.store = store
        self.outbox = outbox
        self.inbox = inbox
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        super.init()
        let configuration: URLSessionConfiguration
        if let identifier {
            configuration = .background(withIdentifier: identifier)
            configuration.sessionSendsLaunchEvents = true
            configuration.isDiscretionary = false
        } else {
            configuration = .default
        }
        configuration.allowsCellularAccess = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.waitsForConnectivity = true
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    /// iOS calls the app with this when it relaunches it to finish background transfers; call it when done.
    public func setBackgroundCompletionHandler(_ handler: @escaping @Sendable () -> Void) {
        completionHandler.withLock { $0 = handler }
    }

    /// Encrypts a file and hands it to iOS to upload. Returns once it's queued, not when it's arrived: watch
    /// ``events`` for that.
    public func upload(fileAt url: URL, as offer: FileOffer, pairing: PairedDevice, from device: DeviceID, to server: URL) async throws {
        let salt = FileCipher.makeSalt()
        let key = FileCipher.key(secret: pairing.secret, salt: salt)
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        let sealedFile = outbox.appending(path: "\(offer.id.uuidString).sealed")
        try await Self.encrypt(url, to: sealedFile, key: key)

        var request = URLRequest(url: server.appending(path: "v1/files"))
        request.httpMethod = "PUT"
        request.setValue(device.rawValue, forHTTPHeaderField: BackgroundProtocol.deviceHeader)
        request.setValue(salt.base64URL, forHTTPHeaderField: BackgroundProtocol.saltHeader)
        request.setValue(try FileCipher.seal(JSONEncoder().encode(offer), key: key).base64URL, forHTTPHeaderField: BackgroundProtocol.offerHeader)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let task = session.uploadTask(with: request, fromFile: sealedFile)
        task.taskDescription = Self.describe(TaskInfo(kind: .upload, offer: offer, peer: pairing.id, sealedFile: sealedFile.path(percentEncoded: false)))
        task.resume()
    }

    /// Hands a file the Mac offered to iOS to download.
    public func download(_ offered: BackgroundOffer, pairing: PairedDevice, as device: DeviceID, from server: URL) {
        var request = URLRequest(url: server.appending(path: "v1/files/\(offered.token)"))
        request.setValue(device.rawValue, forHTTPHeaderField: BackgroundProtocol.deviceHeader)
        let task = session.downloadTask(with: request)
        task.taskDescription = Self.describe(TaskInfo(kind: .download, offer: offered.offer, peer: pairing.id, salt: offered.salt))
        task.resume()
    }

    public func cancel(_ id: UUID) async {
        for task in await session.allTasks where Self.info(of: task)?.offer.id == id { task.cancel() }
    }

    // MARK: -

    @concurrent
    private static func encrypt(_ source: URL, to destination: URL, key: SymmetricKey) async throws {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        try FileCipher.encryptFile(at: source, to: destination, key: key)
    }

    private static func describe(_ info: TaskInfo) -> String? {
        (try? JSONEncoder().encode(info)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func info(of task: URLSessionTask) -> TaskInfo? {
        task.taskDescription.flatMap { try? JSONDecoder().decode(TaskInfo.self, from: Data($0.utf8)) }
    }

    private func finishDownload(_ info: TaskInfo, sealedAt location: URL, response: URLResponse?) {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            continuation.yield(.failed(info.offer.id, reason: String(localized: "The Mac doesn't have that file any more.")))
            return
        }
        guard let salt = info.salt, let pairing = store.pairing(for: info.peer) else {
            continuation.yield(.failed(info.offer.id, reason: String(localized: "This Mac isn't paired any more.")))
            return
        }
        let folder = inbox.appending(path: info.offer.id.uuidString, directoryHint: .isDirectory)
        let destination = folder.appending(path: FileNames.sanitized(info.offer.name))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileCipher.decryptFile(at: location, to: destination, key: FileCipher.key(secret: pairing.secret, salt: salt))
            continuation.yield(.downloaded(info.offer, destination, from: info.peer))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            continuation.yield(.failed(info.offer.id, reason: String(localized: "The file didn't arrive intact.")))
        }
    }
}

extension BackgroundTransfers: URLSessionDataDelegate, URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                           totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let info = Self.info(of: task) else { return }
        let expected = max(1, totalBytesExpectedToSend)
        continuation.yield(.progress(info.offer.id, completed: min(info.offer.byteCount, totalBytesSent * info.offer.byteCount / expected)))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let info = Self.info(of: downloadTask) else { return }
        let expected = max(1, totalBytesExpectedToWrite)
        continuation.yield(.progress(info.offer.id, completed: min(info.offer.byteCount, totalBytesWritten * info.offer.byteCount / expected)))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file at `location` is deleted as soon as this returns, so it's dealt with here and now.
        guard let info = Self.info(of: downloadTask) else { return }
        finishDownload(info, sealedAt: location, response: downloadTask.response)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let info = Self.info(of: task) else { return }
        if let path = info.sealedFile { try? FileManager.default.removeItem(atPath: path) }
        switch info.kind {
        case .upload:
            if error == nil, (task.response as? HTTPURLResponse)?.statusCode == 201 {
                continuation.yield(.uploaded(info.offer.id))
            } else {
                continuation.yield(.failed(info.offer.id, reason: error?.localizedDescription ?? String(localized: "The Mac turned the file down.")))
            }
        case .download:
            if let error, (error as? URLError)?.code != .cancelled {
                continuation.yield(.failed(info.offer.id, reason: error.localizedDescription))
            }
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = completionHandler.withLock { handler in defer { handler = nil }; return handler }
        if let handler { DispatchQueue.main.async(execute: handler) }
    }
}
