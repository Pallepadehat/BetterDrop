import Foundation

/// How close the phone is to the Mac, measured over Bluetooth.
public enum Proximity: Int, Codable, Sendable, Comparable, CaseIterable {
    /// Out of range, or we can't tell.
    case away
    /// In the same room.
    case nearby
    /// Right next to it: this is when the screens light up.
    case touching

    public static func < (lhs: Proximity, rhs: Proximity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Which side of the Mac the phone is held on, so the phone knows where its light and ripples come from.
public enum Side: String, Codable, Sendable, CaseIterable {
    case left, right
}

/// A file one side would like to send.
public struct FileOffer: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var byteCount: Int64
    public var contentTypeIdentifier: String
    public var aspectRatio: Double?

    public init(id: UUID = UUID(), name: String, byteCount: Int64, contentTypeIdentifier: String, aspectRatio: Double? = nil) {
        self.id = id
        self.name = name
        self.byteCount = byteCount
        self.contentTypeIdentifier = contentTypeIdentifier
        self.aspectRatio = aspectRatio
    }

    public init(_ item: DropItem) {
        self.init(name: item.name, byteCount: item.byteCount, contentTypeIdentifier: item.contentTypeIdentifier,
                  aspectRatio: item.aspectRatio)
    }
}

/// A big file the Mac has ready for the phone to fetch in the background, over HTTP.
public struct BackgroundOffer: Codable, Sendable, Hashable {
    public var offer: FileOffer
    /// Names the file on the Mac's file server. Random; only good for this file.
    public var token: String
    /// Mixed with the pairing secret to make this file's key (see ``FileCipher``).
    public var salt: Data

    public init(offer: FileOffer, token: String, salt: Data) {
        self.offer = offer
        self.token = token
        self.salt = salt
    }
}

/// Where the Mac's file server can be reached.
public struct FileServerAddress: Codable, Sendable, Hashable {
    public var port: UInt16
    /// The Mac's IPv4 addresses, best first. iOS's background downloader needs a plain address it can route to.
    public var hosts: [String]

    public init(port: UInt16, hosts: [String]) {
        self.port = port
        self.hosts = hosts
    }
}

/// Everything two paired devices say to each other once the connection is encrypted.
public enum Message: Sendable, Equatable {
    /// "I'd like to send you this." The other side answers with ``accept(_:)`` or ``decline(_:reason:)``.
    case offer(FileOffer)
    case accept(UUID)
    case decline(UUID, reason: String)
    /// A piece of the file, in order, starting at `offset`.
    case chunk(UUID, offset: UInt64, Data)
    /// All the pieces are sent; the receiver checks the whole file against this digest.
    case complete(UUID, sha256: Data)
    /// The receiver has the file, checked and saved.
    case received(UUID)
    /// Either side gave up on a transfer.
    case cancel(UUID)
    /// The phone telling the Mac how close it is, so the Mac's edge can glow.
    case proximity(Proximity)
    /// How close the phone is, from 0 (far) to 1 (touching), sent many times a second so the Mac's light can follow
    /// the phone smoothly.
    case closeness(Double)
    /// The Mac telling the phone which side of it the phone sits.
    case side(Side)
    /// The Mac's file server, for files too big to wait for.
    case fileServer(FileServerAddress)
    /// The Mac has a big file for the phone; fetch it in the background.
    case backgroundOffer(BackgroundOffer)
    /// A device renamed itself.
    case rename(String)
    case ping
    case pong
}
