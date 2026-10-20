import BetterDropCore
import Testing
@testable import BetterDropTransport

@MainActor
struct ProximityTests {
    @Test func levelsHaveHysteresis() {
        #expect(ProximityScanner.level(for: -90, from: .away) == .away)
        #expect(ProximityScanner.level(for: -70, from: .away) == .nearby)
        #expect(ProximityScanner.level(for: -45, from: .away) == .touching)
        // Drifting a little weaker doesn't drop out of touching…
        #expect(ProximityScanner.level(for: -52, from: .touching) == .touching)
        // …but the same reading isn't enough to get into it.
        #expect(ProximityScanner.level(for: -52, from: .nearby) == .nearby)
        #expect(ProximityScanner.level(for: -60, from: .touching) == .nearby)
        #expect(ProximityScanner.level(for: -78, from: .nearby) == .nearby)
        #expect(ProximityScanner.level(for: -85, from: .nearby) == .away)
    }

    @Test func closenessIsSmoothAndClamped() {
        #expect(ProximityScanner.closeness(for: -100) == 0)
        #expect(ProximityScanner.closeness(for: -30) == 1)
        #expect(ProximityScanner.closeness(for: -60) > ProximityScanner.closeness(for: -70))
    }

    @Test func beaconNamesCarryTheShortID() {
        let id = DeviceID.random()
        let name = ProximityConfiguration.localName(for: id)
        #expect(name.utf8.count <= 10)
        #expect(ProximityConfiguration.shortID(fromLocalName: name) == id.short)
        #expect(ProximityConfiguration.shortID(fromLocalName: "AirPods") == nil)
        #expect(ProximityConfiguration.shortID(fromLocalName: "BD") == nil)
    }
}
