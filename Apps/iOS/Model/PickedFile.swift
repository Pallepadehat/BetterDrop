import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A file handed over by the photo picker, copied somewhere we can keep it (the picker's copy disappears).
nonisolated struct PickedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { try PickedFile(copying: $0.file) }
        FileRepresentation(importedContentType: .image) { try PickedFile(copying: $0.file) }
        FileRepresentation(importedContentType: .item) { try PickedFile(copying: $0.file) }
    }

    init(copying file: URL) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: url)
    }
}
