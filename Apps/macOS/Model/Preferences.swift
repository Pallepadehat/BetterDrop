import BetterDropUI
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

    /// Which side of the screen the phone sits on: the light comes out of that edge.
    var edge: EdgeBloom.Edge {
        didSet { defaults.set(edge.rawValue, forKey: Keys.edge) }
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
        edge = defaults.string(forKey: Keys.edge).flatMap(EdgeBloom.Edge.init(rawValue:)) ?? .trailing
        revealReceivedFiles = defaults.object(forKey: Keys.reveal) as? Bool ?? false
        playsSounds = defaults.object(forKey: Keys.sounds) as? Bool ?? true
    }

    private enum Keys {
        static let deviceName = "deviceName"
        static let edge = "edge"
        static let reveal = "revealReceivedFiles"
        static let sounds = "playsSounds"
    }
}
