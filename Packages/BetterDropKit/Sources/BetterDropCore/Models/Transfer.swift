import Foundation
import UniformTypeIdentifiers

/// A file on its way somewhere, for showing progress.
public struct Transfer: Identifiable, Sendable, Hashable {
    public enum Direction: Sendable, Hashable { case incoming, outgoing }

    public let id: UUID
    public let name: String
    public let byteCount: Int64
    public let contentTypeIdentifier: String
    public let direction: Direction
    public let peerName: String
    public var completed: Int64 = 0
    /// For outgoing files: the library item being sent.
    public var itemID: UUID?
    public var aspectRatio: Double?

    public init(offer: FileOffer, direction: Direction, peerName: String, itemID: UUID? = nil) {
        id = offer.id
        name = offer.name
        byteCount = offer.byteCount
        contentTypeIdentifier = offer.contentTypeIdentifier
        self.direction = direction
        self.peerName = peerName
        self.itemID = itemID
        aspectRatio = offer.aspectRatio
    }

    public var fraction: Double {
        byteCount > 0 ? min(1, Double(completed) / Double(byteCount)) : 1
    }

    public var kind: DropItem.Kind { DropItem.Kind(UTType(contentTypeIdentifier) ?? .data) }
}
