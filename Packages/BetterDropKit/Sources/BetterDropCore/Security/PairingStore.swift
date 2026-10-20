import Foundation
import Security
import Synchronization

/// Where pairing secrets are kept.
public protocol PairingStore: Sendable {
    func all() -> [PairedDevice]
    func save(_ device: PairedDevice) throws
    func remove(_ id: DeviceID) throws
}

public extension PairingStore {
    func pairing(for id: DeviceID) -> PairedDevice? { all().first { $0.id == id } }
}

/// Keeps pairings in the data protection keychain, readable only while the device is unlocked. Used on iPhone.
public struct KeychainPairingStore: PairingStore {
    private let service: String

    public init(service: String = "BetterDrop pairing") {
        self.service = service
    }

    private var base: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecUseDataProtectionKeychain: true]
    }

    public func all() -> [PairedDevice] {
        var query = base
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitAll
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [Data] else { return [] }
        return items.compactMap { try? JSONDecoder().decode(PairedDevice.self, from: $0) }
    }

    public func save(_ device: PairedDevice) throws {
        try? remove(device.id)
        var item = base
        item[kSecAttrAccount] = device.id.rawValue
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecValueData] = try JSONEncoder().encode(device)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func remove(_ id: DeviceID) throws {
        var query = base
        query[kSecAttrAccount] = id.rawValue
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    public struct KeychainError: Error, CustomStringConvertible {
        public let status: OSStatus
        public var description: String { (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)" }
    }
}

/// Keeps pairings in a file only you can read (mode 0600).
///
/// Used on the Mac: releases are signed ad hoc (no Apple Developer ID yet), so each update looks like a different
/// app to the login keychain, which would then ask for your password after every update. The file lives in
/// Application Support, which is as private as anything else in your home folder.
public struct FilePairingStore: PairingStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func all() -> [PairedDevice] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PairedDevice].self, from: data)) ?? []
    }

    public func save(_ device: PairedDevice) throws {
        var devices = all().filter { $0.id != device.id }
        devices.append(device)
        try write(devices)
    }

    public func remove(_ id: DeviceID) throws {
        try write(all().filter { $0.id != id })
    }

    private func write(_ devices: [PairedDevice]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(devices).write(to: url, options: [.atomic, .completeFileProtection])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
    }
}

/// Keeps pairings in memory. For tests and previews.
public final class MemoryPairingStore: PairingStore {
    private let devices: Mutex<[DeviceID: PairedDevice]>

    public init(_ devices: [PairedDevice] = []) {
        self.devices = Mutex(Dictionary(devices.map { ($0.id, $0) }, uniquingKeysWith: { $1 }))
    }

    public func all() -> [PairedDevice] { devices.withLock { Array($0.values) } }
    public func save(_ device: PairedDevice) throws { devices.withLock { $0[device.id] = device } }
    public func remove(_ id: DeviceID) throws { _ = devices.withLock { $0.removeValue(forKey: id) } }
}
