import Foundation
import UniformTypeIdentifiers

/// One file in the library: something you sent, received or added yourself.
public struct DropItem: Identifiable, Codable, Sendable, Hashable {
    public enum Origin: Codable, Sendable, Hashable {
        /// Added on this device (from Photos, Files, a drag…).
        case added
        /// Arrived from another device.
        case received(from: String)
    }

    public var id: UUID
    /// The file name, as shown and as saved.
    public var name: String
    public var byteCount: Int64
    /// A uniform type identifier, such as `public.jpeg`.
    public var contentTypeIdentifier: String
    public var addedAt: Date
    public var origin: Origin
    /// Width over height, when it's a picture or a video. Lets the grid lay itself out before thumbnails load.
    public var aspectRatio: Double?

    public init(
        id: UUID = UUID(),
        name: String,
        byteCount: Int64,
        contentTypeIdentifier: String,
        addedAt: Date = .now,
        origin: Origin = .added,
        aspectRatio: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.byteCount = byteCount
        self.contentTypeIdentifier = contentTypeIdentifier
        self.addedAt = addedAt
        self.origin = origin
        self.aspectRatio = aspectRatio
    }

    public var contentType: UTType { UTType(contentTypeIdentifier) ?? .data }

    public var kind: Kind { Kind(contentType) }

    /// Broad families of files, which decide how a card is drawn.
    public enum Kind: Sendable, Hashable {
        case image, video, audio, pdf, text, archive, other

        public init(_ type: UTType) {
            if type.conforms(to: .image) { self = .image }
            else if type.conforms(to: .movie) || type.conforms(to: .video) { self = .video }
            else if type.conforms(to: .audio) { self = .audio }
            else if type.conforms(to: .pdf) { self = .pdf }
            else if type.conforms(to: .text) || type.conforms(to: .sourceCode) { self = .text }
            else if type.conforms(to: .archive) { self = .archive }
            else { self = .other }
        }

        /// Pictures and videos fill their card; everything else gets drawn as a page.
        public var isVisual: Bool { self == .image || self == .video }
    }

    /// A short badge for the corner of a document card: "PDF", "MD", "ZIP".
    public var badge: String {
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty { return ext.uppercased() }
        return contentType.preferredFilenameExtension?.uppercased() ?? "FILE"
    }
}
