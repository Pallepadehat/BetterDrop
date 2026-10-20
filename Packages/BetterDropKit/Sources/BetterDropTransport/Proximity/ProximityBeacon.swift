import BetterDropCore
@preconcurrency import CoreBluetooth
import Foundation

/// Bluetooth details both sides agree on.
public enum ProximityConfiguration {
    /// The service the Mac advertises. Made up for BetterDrop; nothing connects to it, it's only measured.
    public static let serviceUUID = CBUUID(string: "B7D0F1E2-6C3A-4E8B-9F21-5A7C3D9E0B14")
    /// Advertisements are tiny, so the Mac puts "BD" and the short form of its ``DeviceID`` in its local name.
    static let namePrefix = "BD"

    static func localName(for id: DeviceID) -> String { namePrefix + id.short }

    static func shortID(fromLocalName name: String) -> String? {
        guard name.hasPrefix(namePrefix) else { return nil }
        let id = String(name.dropFirst(namePrefix.count))
        return id.isEmpty ? nil : id
    }
}

/// The Mac's half of proximity: a Bluetooth beacon the phone can measure, so it knows when it's held right next to
/// the Mac. Nothing is sent over it; it's a lighthouse.
@MainActor
public final class ProximityBeacon: NSObject {
    private var manager: CBPeripheralManager?
    private let localName: String
    private var wantsToAdvertise = false

    public init(device: DeviceID) {
        localName = ProximityConfiguration.localName(for: device)
    }

    public func start() {
        wantsToAdvertise = true
        if let manager {
            advertise(manager)
        } else {
            manager = CBPeripheralManager(delegate: self, queue: .main)
        }
    }

    public func stop() {
        wantsToAdvertise = false
        manager?.stopAdvertising()
    }

    private func advertise(_ manager: CBPeripheralManager) {
        guard wantsToAdvertise, manager.state == .poweredOn, !manager.isAdvertising else { return }
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [ProximityConfiguration.serviceUUID],
            CBAdvertisementDataLocalNameKey: localName,
        ])
    }
}

extension ProximityBeacon: CBPeripheralManagerDelegate {
    public nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated {
            if peripheral.state == .poweredOn { advertise(peripheral) }
        }
    }

    public nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if let error { Log.proximity.error("Couldn't advertise: \(error.localizedDescription, privacy: .public)") }
    }
}
