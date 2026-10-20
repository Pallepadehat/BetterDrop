import BetterDropCore
import Foundation
import Observation

/// The Mac's settings, kept in UserDefaults.
@Observable
final class Preferences {
    private let defaults: UserDefaults

    /// What phones see this Mac as. Starts as the Mac's own name, like "Patrick's MacBook Pro".
    var deviceName: String {
        didSet { defaults.set(deviceName, forKey: Keys.deviceName) }
    }

    /// Which side of the Mac the phone sits on: the light comes out of that edge.
    var side: Side {
        didSet { defaults.set(side.rawValue, forKey: Keys.side) }
    }

    /// Opens a Finder window on each file as it arrives.
    var revealReceivedFiles: Bool {
        didSet { defaults.set(revealReceivedFiles, forKey: Keys.reveal) }
    }

    var playsSounds: Bool {
        didSet { defaults.set(playsSounds, forKey: Keys.sounds) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deviceName = defaults.string(forKey: Keys.deviceName) ?? Host.current().localizedName ?? String(localized: "Mac")
        side = defaults.string(forKey: Keys.side).flatMap(Side.init(rawValue:)) ?? .right
        revealReceivedFiles = defaults.object(forKey: Keys.reveal) as? Bool ?? false
        playsSounds = defaults.object(forKey: Keys.sounds) as? Bool ?? true
    }

    private enum Keys {
        static let deviceName = "deviceName"
        static let side = "side"
        static let reveal = "revealReceivedFiles"
        static let sounds = "playsSounds"
    }
}
