import Foundation

/// A stable identifier for one install of BetterDrop. Made once, kept forever (see ``LocalDevice``).
public struct DeviceID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public static func random() -> DeviceID { DeviceID(rawValue: UUID().uuidString.lowercased()) }

    /// The first eight characters. Short enough for a Bluetooth advertisement, long enough not to clash on one desk.
    public var short: String { String(rawValue.replacingOccurrences(of: "-", with: "").prefix(8)) }

    public var description: String { rawValue }
}

public enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case mac, iPhone, iPad

    public var symbolName: String {
        switch self {
        case .mac: "laptopcomputer"
        case .iPhone: "iphone"
        case .iPad: "ipad"
        }
    }
}

/// What a device says about itself when it connects.
public struct DeviceInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: DeviceID
    public var name: String
    public var kind: DeviceKind

    public init(id: DeviceID, name: String, kind: DeviceKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}
