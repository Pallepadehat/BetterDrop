import Foundation

/// This device's identity: made the first time BetterDrop runs and kept from then on, so pairings survive restarts.
public enum LocalDevice {
    private static let key = "BetterDrop.deviceID"

    public static func id(in defaults: UserDefaults = .standard) -> DeviceID {
        if let stored = defaults.string(forKey: key), !stored.isEmpty { return DeviceID(rawValue: stored) }
        let id = DeviceID.random()
        defaults.set(id.rawValue, forKey: key)
        return id
    }
}
