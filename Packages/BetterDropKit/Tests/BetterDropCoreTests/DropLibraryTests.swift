import Foundation
import Testing
@testable import BetterDropCore

@MainActor
struct DropLibraryTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "DropLibraryTests-\(UUID().uuidString)")

    private func makeFile(_ name: String, bytes: Int = 16) throws -> URL {
        let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
        try Data(repeating: 7, count: bytes).write(to: source)
        return source
    }

    @Test func addsCopiesNewestFirstAndRemembers() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try DropLibrary(directory: folder)
        let first = try await library.add(fileAt: makeFile("notes.md"), named: "Meeting notes.md")
        let second = try await library.add(fileAt: makeFile("report.pdf", bytes: 2048), named: "Q4 Report.pdf",
                                           origin: .received(from: "Patrick's iPhone"))

        #expect(library.items.map(\.id) == [second.id, first.id])
        #expect(second.byteCount == 2048)
        #expect(second.kind == .pdf)
        #expect(first.kind == .text)
        #expect(second.badge == "PDF")

        let reopened = try DropLibrary(directory: folder)
        #expect(reopened.items.map(\.id) == [second.id, first.id])
        #expect(reopened.items.first?.origin == .received(from: "Patrick's iPhone"))
    }

    @Test func movesWhenAskedAndNeverEscapesTheFolder() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try DropLibrary(directory: folder)
        let source = try makeFile("x")
        let item = try await library.add(fileAt: source, named: "../../escape.txt", move: true)

        #expect(item.name == "escape.txt")
        #expect(!FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
        #expect(library.url(for: item).deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
    }

    @Test func forgetsDeletedFilesAndAdoptsNewOnes() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try DropLibrary(directory: folder)
        let gone = try await library.add(fileAt: makeFile("a.txt"))
        try FileManager.default.removeItem(at: library.url(for: gone))
        try Data("hi".utf8).write(to: folder.appending(path: "dropped in Finder.txt"))

        library.refresh()
        #expect(library.items.map(\.name) == ["dropped in Finder.txt"])
    }

    @Test func removeDeletesTheFile() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try DropLibrary(directory: folder)
        let item = try await library.add(fileAt: makeFile("walrus.jpg"))
        library.remove(item)
        #expect(library.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: library.url(for: item).path(percentEncoded: false)))
    }
}
