import BetterDropCore
import Foundation

public extension DropItem {
    /// "367 KB · 13:25", as under each card.
    var caption: String {
        "\(byteCount.formatted(.byteCount(style: .file))) · \(addedAt.formatted(date: .omitted, time: .shortened))"
    }
}

public extension Int64 {
    var fileSize: String { formatted(.byteCount(style: .file)) }
}
