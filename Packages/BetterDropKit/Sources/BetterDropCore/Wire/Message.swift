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
    /// A device renamed itself.
    case rename(String)
    case ping
    case pong
}
