import Foundation
import Observation
import UniformTypeIdentifiers

/// The files on this device that BetterDrop knows about, newest first.
///
/// Files live as ordinary files in ``directory`` (on the Mac that's `~/Downloads/BetterDrop`, so Finder sees them
/// too) and a small index next to them remembers where each came from. Delete a file behind BetterDrop's back and it
/// quietly leaves the library the next time it loads.
@MainActor
@Observable
public final class DropLibrary {
    public private(set) var items: [DropItem] = []
    public let directory: URL

    @ObservationIgnored private let indexURL: URL
    @ObservationIgnored private let fileManager = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        let hidden = directory.appending(path: ".betterdrop", directoryHint: .isDirectory)
        indexURL = hidden.appending(path: "index.json")
        try fileManager.createDirectory(at: hidden, withIntermediateDirectories: true)
        load()
    }

    public func url(for item: DropItem) -> URL {
        directory.appending(path: item.name)
    }

    public func item(withID id: UUID) -> DropItem? {
        items.first { $0.id == id }
    }

    public var totalByteCount: Int64 { items.reduce(0) { $0 + $1.byteCount } }

    /// Brings a file into the library. With `move` the original is moved in (for files that only exist for us,
    /// such as a download in a temporary folder); otherwise it's copied.
    @discardableResult
    public func add(fileAt source: URL, named proposedName: String? = nil, origin: DropItem.Origin = .added,
                    move: Bool = false) async throws -> DropItem {
        let name = FileNames.unique(FileNames.sanitized(proposedName ?? source.lastPathComponent), in: directory)
        let destination = directory.appending(path: name)
        let item = try await Self.place(source, at: destination, name: name, origin: origin, move: move)
        items.insert(item, at: 0)
        save()
        return item
    }

    public func remove(_ item: DropItem) {
        try? fileManager.removeItem(at: url(for: item))
        items.removeAll { $0.id == item.id }
        save()
    }

    public func removeAll() {
        for item in items { try? fileManager.removeItem(at: url(for: item)) }
        items.removeAll()
        save()
    }

    /// Picks up files that were deleted, or dropped into the folder, while BetterDrop wasn't looking.
    public func refresh() {
        load()
    }

    // MARK: - Disk

    /// Copies or moves the file and works out what it is, away from the main thread: a video can be gigabytes.
    @concurrent
    private static func place(_ source: URL, at destination: URL, name: String, origin: DropItem.Origin,
                              move: Bool) async throws -> DropItem {
        let fileManager = FileManager.default
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        if move {
            try fileManager.moveItem(at: source, to: destination)
        } else {
            try fileManager.copyItem(at: source, to: destination)
        }
        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let type = MediaInspector.contentType(of: destination)
        let ratio = await MediaInspector.aspectRatio(of: destination, type: type)
        return DropItem(name: name, byteCount: size, contentTypeIdentifier: type.identifier,
                        origin: origin, aspectRatio: ratio)
    }

    private func load() {
        var known: [DropItem] = []
        if let data = try? Data(contentsOf: indexURL) {
            known = (try? JSONDecoder.library.decode([DropItem].self, from: data)) ?? []
        }
        // Keep what's still there, then adopt anything new that was put in the folder by hand.
        known.removeAll { !fileManager.fileExists(atPath: url(for: $0).path(percentEncoded: false)) }
        let knownNames = Set(known.map(\.name))
        let onDisk = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentTypeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles])) ?? []
        for url in onDisk where !knownNames.contains(url.lastPathComponent) {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentTypeKey, .isRegularFileKey]),
                  values.isRegularFile == true
            else { continue }
            known.append(DropItem(
                name: url.lastPathComponent,
                byteCount: Int64(values.fileSize ?? 0),
                contentTypeIdentifier: (values.contentType ?? .data).identifier,
                addedAt: values.creationDate ?? .now))
        }
        items = known.sorted { $0.addedAt > $1.addedAt }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder.library.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var library: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var library: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
