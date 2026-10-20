import BetterDropCore
@preconcurrency import CoreBluetooth
import Foundation
import Observation

/// The phone's half of proximity: listens for Macs' beacons and turns their signal strength into ``Proximity``.
///
/// Bluetooth signal strength is noisy, so readings are smoothed, and each level is entered at a stronger signal
/// than it's left at, so holding the phone still doesn't make the glow flicker.
@MainActor
@Observable
public final class ProximityScanner: NSObject {
    public enum Availability: Equatable, Sendable {
        case unknown
        case available
        /// Bluetooth is off, not allowed, or missing (the Simulator). Everything still works, just without the
        /// "hold it close" part.
        case unavailable
    }

    public private(set) var availability: Availability = .unknown
    /// By short device ID.
    public private(set) var proximities: [String: Proximity] = [:]
    /// How close each Mac is, from 0 (out of range) to 1 (touching), smoothly, by short device ID.
    public private(set) var closenesses: [String: Double] = [:]

    @ObservationIgnored private var manager: CBCentralManager?
    @ObservationIgnored private var readings: [String: Reading] = [:]
    @ObservationIgnored private var decay: Task<Void, Never>?

    private struct Reading {
        var smoothed: Double
        var lastSeen: ContinuousClock.Instant
        var level: Proximity
    }

    /// Signal strengths (dBm) to step up to a level, and to drop back below it.
    static let thresholds: [(level: Proximity, enter: Double, leave: Double)] = [
        (.touching, -48, -56),
        (.nearby, -72, -80),
    ]

    public func proximity(of id: DeviceID) -> Proximity {
        proximities[id.short] ?? .away
    }

    public func closeness(of id: DeviceID) -> Double {
        closenesses[id.short] ?? 0
    }

    /// Signal strengths mapped onto closeness: -85 dBm and weaker is 0, -38 dBm and stronger is 1.
    static func closeness(for rssi: Double) -> Double {
        let value = (rssi + 85) / 47
        return min(1, max(0, value))
    }

    public func start() {
        if let manager {
            scan(manager)
        } else {
            manager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
        decay = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.forgetQuietBeacons()
            }
        }
    }

    public func stop() {
        manager?.stopScan()
        decay?.cancel()
        decay = nil
        readings.removeAll()
        proximities.removeAll()
        closenesses.removeAll()
    }

    private func scan(_ manager: CBCentralManager) {
        guard manager.state == .poweredOn, !manager.isScanning else { return }
        manager.scanForPeripherals(withServices: [ProximityConfiguration.serviceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    fileprivate func heard(_ shortID: String, rssi: Double) {
        // 127 means "no reading"; anything at or above zero is nonsense.
        guard rssi < 0 else { return }
        var reading = readings[shortID] ?? Reading(smoothed: rssi, lastSeen: .now, level: .away)
        reading.smoothed = reading.smoothed * 0.7 + rssi * 0.3
        reading.lastSeen = .now
        reading.level = Self.level(for: reading.smoothed, from: reading.level)
        readings[shortID] = reading
        if proximities[shortID] != reading.level { proximities[shortID] = reading.level }
        let closeness = Self.closeness(for: reading.smoothed)
        // Small wobbles aren't worth redrawing for.
        if abs((closenesses[shortID] ?? -1) - closeness) > 0.015 { closenesses[shortID] = closeness }
    }

    static func level(for rssi: Double, from current: Proximity) -> Proximity {
        for threshold in thresholds {
            let boundary = current >= threshold.level ? threshold.leave : threshold.enter
            if rssi >= boundary { return threshold.level }
        }
        return .away
    }

    private func forgetQuietBeacons() {
        let cutoff = ContinuousClock.now - .seconds(3)
        for (id, reading) in readings where reading.lastSeen < cutoff {
            readings[id] = nil
            proximities[id] = nil
            closenesses[id] = nil
        }
    }
}

extension ProximityScanner: CBCentralManagerDelegate {
    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn:
                availability = .available
                scan(central)
            case .unknown, .resetting:
                availability = .unknown
            default:
                availability = .unavailable
                proximities.removeAll()
                closenesses.removeAll()
            }
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                           advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              let id = ProximityConfiguration.shortID(fromLocalName: name)
        else { return }
        let rssi = RSSI.doubleValue
        MainActor.assumeIsolated { heard(id, rssi: rssi) }
    }
}
