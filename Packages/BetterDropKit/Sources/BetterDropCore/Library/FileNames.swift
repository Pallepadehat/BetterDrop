import Foundation

/// File names that arrive from another device are untrusted: they could try to climb out of the library folder
/// (`../../.zshrc`), hide themselves (`.secret`) or be empty. Everything that names a file on disk goes through here.
public enum FileNames {
    /// The longest name we'll write. APFS allows 255 UTF-8 bytes; this leaves room for " 99" before the extension.
    static let maximumLength = 200

    public static func sanitized(_ proposed: String) -> String {
        // Only the last path component counts, whichever separator was used.
        var name = proposed
            .split(whereSeparator: { $0 == "/" || $0 == "\\" || $0 == ":" })
            .last
            .map(String.init) ?? ""
        name = name.filter { !$0.isNewline && $0 != "\0" && !($0.unicodeScalars.first?.properties.generalCategory == .control) }
        name = name.trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "File" }

        if name.utf8.count > maximumLength {
            let ext = (name as NSString).pathExtension
            var stem = (name as NSString).deletingPathExtension
            while (stem.utf8.count + ext.utf8.count + 1) > maximumLength, !stem.isEmpty { stem.removeLast() }
            name = ext.isEmpty ? stem : "\(stem).\(ext)"
        }
        return name
    }

    /// `name`, or "name 2", "name 3"… if something in `directory` already has it.
    public static func unique(_ name: String, in directory: URL, fileManager: FileManager = .default) -> String {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var candidate = name
        var counter = 2
        while fileManager.fileExists(atPath: directory.appending(path: candidate).path(percentEncoded: false)) {
            candidate = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            counter += 1
        }
        return candidate
    }
}
