import Foundation
import Testing
@testable import BetterDropCore

struct FileNamesTests {
    @Test(arguments: [
        ("../../.zshrc", "zshrc"),
        ("/etc/passwd", "passwd"),
        ("..\\..\\boot.ini", "boot.ini"),
        ("Q4 Report.pdf", "Q4 Report.pdf"),
        ("", "File"),
        ("...", "File"),
        ("  Golden Hour.jpg  ", "Golden Hour.jpg"),
        ("line\nbreak.txt", "linebreak.txt"),
        ("Mac:Old:Style", "Style"),
    ])
    func sanitizesUntrustedNames(input: String, expected: String) {
        #expect(FileNames.sanitized(input) == expected)
    }

    @Test func keepsTheExtensionWhenShortening() {
        let long = String(repeating: "a", count: 400) + ".mov"
        let name = FileNames.sanitized(long)
        #expect(name.utf8.count <= FileNames.maximumLength)
        #expect(name.hasSuffix(".mov"))
    }

    @Test func numbersNamesThatAreTaken() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(FileNames.unique("walrus.jpg", in: folder) == "walrus.jpg")
        try Data().write(to: folder.appending(path: "walrus.jpg"))
        #expect(FileNames.unique("walrus.jpg", in: folder) == "walrus 2.jpg")
        try Data().write(to: folder.appending(path: "walrus 2.jpg"))
        #expect(FileNames.unique("walrus.jpg", in: folder) == "walrus 3.jpg")
        try Data().write(to: folder.appending(path: "README"))
        #expect(FileNames.unique("README", in: folder) == "README 2")
    }
}
