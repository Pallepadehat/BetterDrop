import BetterDropCore
import BetterDropTransport
import Foundation
import Observation
import os
import Photos
import UIKit

/// Everything the iPhone app knows: the Mac it's paired with, whether it's connected, how close it is, and the
/// files on their way.
@Observable
final class PhoneModel {
    enum Connection: Equatable {
        case idle
        case connecting
        case connected
    }

    enum Pairing: Equatable {
        case idle
        case connecting
        /// Waiting for you to accept on the Mac.
        case confirming(code: String)
        case failed(String)
    }

    let library: DropLibrary
    let browser: DeviceBrowser
    let scanner = ProximityScanner()
    private(set) var device: DeviceInfo
    private(set) var pairedMac: PairedDevice?
    private(set) var connection = Connection.idle
    private(set) var pairing = Pairing.idle
    private(set) var transfers: [UUID: Transfer] = [:]
    /// Bumped each time a file arrives or leaves, for haptics and a burst of light.
    private(set) var arrivals = 0
    private(set) var departures = 0
    private(set) var flash = false
    /// Bumped for every burst of light: something arrived, left, or we just connected.
    private(set) var bursts = 0
    /// Which edge of this screen faces the Mac. The Mac says which side of it we're on; until then, the left, as
    /// most people hold the phone to the right of the laptop.
    private(set) var macSide = EdgeSide.left
    var lastError: String?

    @ObservationIgnored private let store: any PairingStore = KeychainPairingStore()
    @ObservationIgnored private var link: Link?
    @ObservationIgnored private var maintaining: Task<Void, Never>?
    @ObservationIgnored private var reportingProximity: Task<Void, Never>?
    @ObservationIgnored private var reportingCloseness: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "BetterDrop", category: "phone")
    @ObservationIgnored private static let nameKey = "deviceName"

    init() {
        let documents = URL.documentsDirectory
        library = (try? DropLibrary(directory: documents))
            ?? (try! DropLibrary(directory: URL.applicationSupportDirectory.appending(path: "Library")))
        let id = LocalDevice.id()
        let name = UserDefaults.standard.string(forKey: Self.nameKey) ?? UIDevice.current.name
        device = DeviceInfo(id: id, name: name, kind: UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone)
        browser = DeviceBrowser(ignoring: id)
        pairedMac = store.all().max { $0.pairedAt < $1.pairedAt }
    }

    // MARK: - Running

    func resume() {
        browser.start()
        scanner.start()
        guard maintaining == nil else { return }
        maintaining = Task { await maintainConnection() }
        reportingProximity = Task { await reportProximity() }
        reportingCloseness = Task { await reportCloseness() }
        #if DEBUG
        runDemo()
        #endif
    }

    func suspend() {
        scanner.stop()
        maintaining?.cancel()
        maintaining = nil
        reportingProximity?.cancel()
        reportingProximity = nil
        reportingCloseness?.cancel()
        reportingCloseness = nil
    }

    /// Keeps a connection to the paired Mac whenever it can be seen on the network.
    private func maintainConnection() async {
        while !Task.isCancelled {
            if link == nil, pairing == .idle, let paired = pairedMac,
               let found = browser.devices.first(where: { $0.id == paired.id }) {
                await connect(to: found, with: paired)
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    /// Tells the Mac how close we are, whenever it changes, so its edge can glow.
    private func reportProximity() async {
        let changes = Observations { [weak self] in
            self.map { model in model.pairedMac.map { model.scanner.proximity(of: $0.id) } ?? .away }
        }
        for await proximity in changes {
            guard let proximity, let link else { continue }
            try? await link.send(.proximity(proximity))
        }
    }

    /// The smooth version, at most fifteen times a second, for the Mac's light to follow.
    private func reportCloseness() async {
        let changes = Observations { [weak self] in
            self.map { model in model.pairedMac.map { model.scanner.closeness(of: $0.id) } ?? 0 }
        }
        var lastSent = ContinuousClock.now - .seconds(1)
        for await closeness in changes {
            guard let closeness, let link, ContinuousClock.now - lastSent > .milliseconds(66) else { continue }
            lastSent = .now
            try? await link.send(.closeness(closeness))
        }
    }

    /// How close the paired Mac is, 0 to 1.
    var closeness: Double {
        pairedMac.map { scanner.closeness(of: $0.id) } ?? 0
    }

    func closeness(of mac: DiscoveredDevice) -> Double { scanner.closeness(of: mac.id) }

    // MARK: - Pairing

    /// The Mac to pair with: the one you're holding the phone to, or failing that, the only one around.
    var candidateMac: DiscoveredDevice? {
        let devices = browser.devices
        return devices.max { scanner.proximity(of: $0.id) < scanner.proximity(of: $1.id) } ?? devices.first
    }

    func proximity(of mac: DiscoveredDevice) -> Proximity { scanner.proximity(of: mac.id) }

    /// Bluetooth tells us how close the Mac is; without it (the Simulator, Bluetooth off) the button just works.
    var measuresProximity: Bool { scanner.availability == .available }

    func pair(with mac: DiscoveredDevice) async {
        guard pairing == .idle || pairing.isFailure else { return }
        pairing = .connecting
        let connection = FramedConnection(to: mac.endpoint)
        do {
            try await connection.start()
            let paired = try await ClientHandshake.pair(over: connection, as: device) { [weak self] code in
                await MainActor.run { self?.pairing = .confirming(code: code) }
            }
            try store.save(paired)
            pairedMac = paired
            let (channel, peer) = try await ClientHandshake.startSession(over: connection, as: device, with: paired)
            attach(Link(channel: channel, peer: peer))
            pairing = .idle
        } catch {
            connection.cancel()
            pairing = .failed(Self.describe(error))
        }
    }

    func resetPairing() {
        pairing = .idle
    }

    func forgetMac() {
        if let pairedMac { try? store.remove(pairedMac.id) }
        pairedMac = nil
        link?.closeSoon()
        link = nil
        connection = .idle
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != device.name else { return }
        device.name = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.nameKey)
        if let link { Task { try? await link.send(.rename(trimmed)) } }
    }

    // MARK: - The connection

    private func connect(to mac: DiscoveredDevice, with paired: PairedDevice) async {
        connection = .connecting
        let framed = FramedConnection(to: mac.endpoint)
        do {
            try await framed.start()
            let (channel, peer) = try await ClientHandshake.startSession(over: framed, as: device, with: paired)
            attach(Link(channel: channel, peer: peer))
        } catch HandshakeError.rejected(.unknownDevice) {
            // The Mac forgot us. Pair again.
            framed.cancel()
            log.notice("The Mac doesn't know us any more")
            forgetMac()
        } catch {
            framed.cancel()
            connection = .idle
        }
    }

    private func attach(_ link: Link) {
        self.link?.closeSoon()
        self.link = link
        connection = .connected
        bursts += 1
        if let pairedMac, pairedMac.device.name != link.peer.name {
            var updated = pairedMac
            updated.device = link.peer
            try? store.save(updated)
            self.pairedMac = updated
        }
        Task {
            await link.start()
            try? await link.send(.proximity(scanner.proximity(of: link.peer.id)))
            for await event in link.events {
                handle(event, from: link)
            }
            if self.link === link {
                self.link = nil
                connection = .idle
            }
        }
    }

    private func handle(_ event: LinkEvent, from link: Link) {
        switch event {
        case let .incomingStarted(offer):
            transfers[offer.id] = Transfer(offer: offer, direction: .incoming, peerName: link.peer.name)
            bursts += 1
        case let .progress(id, completed):
            transfers[id]?.completed = completed
        case let .incomingFinished(offer, url):
            Task {
                do {
                    try await library.add(fileAt: url, named: offer.name, origin: .received(from: link.peer.name), move: true)
                    arrivals += 1
                    flashOnce()
                } catch {
                    lastError = error.localizedDescription
                }
                transfers[offer.id] = nil
            }
        case let .outgoingFinished(id):
            transfers[id] = nil
        case let .failed(id, reason):
            if let transfer = transfers.removeValue(forKey: id) {
                lastError = String(localized: "\(transfer.name) didn't make it: \(reason)")
            }
        case let .renamed(name):
            if var paired = pairedMac {
                paired.device.name = name
                try? store.save(paired)
                pairedMac = paired
            }
        case let .side(side):
            macSide = side == .right ? .left : .right
        case .proximity, .closeness:
            break
        case .closed:
            for (id, transfer) in transfers where transfer.peerName == link.peer.name { transfers[id] = nil }
        }
    }

    // MARK: - The glow

    var glowIntensity: Double {
        if flash { return 1 }
        if transfers.values.contains(where: { $0.direction == .incoming }) { return 0.9 }
        if !transfers.isEmpty { return 0.6 }
        guard pairedMac != nil, connection == .connected else { return 0 }
        // Wakes up as the phone nears the Mac, and is plainly there once they touch.
        return max(0, (closeness - 0.45) / 0.55) * 0.55
    }

    private func flashOnce() {
        flashTask?.cancel()
        flash = true
        flashTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            flash = false
        }
    }

    // MARK: - Files

    var isConnected: Bool { connection == .connected }

    func send(_ item: DropItem) {
        guard let link else {
            lastError = String(localized: "Your Mac isn't connected. Open BetterDrop on it, on the same Wi-Fi.")
            return
        }
        let offer = FileOffer(item)
        transfers[offer.id] = Transfer(offer: offer, direction: .outgoing, peerName: link.peer.name, itemID: item.id)
        departures += 1
        bursts += 1
        flashOnce()
        let url = library.url(for: item)
        Task {
            do {
                try await link.send(fileAt: url, as: offer)
            } catch {
                lastError = String(localized: "Couldn't send \(item.name): \(error.localizedDescription)")
            }
            transfers[offer.id] = nil
        }
    }

    func progress(for item: DropItem) -> Double? {
        transfers.values.first { $0.itemID == item.id }?.fraction
    }

    func add(_ urls: [URL], move: Bool = false) async {
        for url in urls {
            do {
                try await library.add(fileAt: url, move: move)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func saveToPhotos(_ item: DropItem) async {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else {
            lastError = String(localized: "BetterDrop isn't allowed to add to your photo library. You can change that in Settings.")
            return
        }
        let url = library.url(for: item)
        let isVideo = item.kind == .video
        do {
            try await PHPhotoLibrary.shared().performChanges {
                if isVideo {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: -

    private static func describe(_ error: any Error) -> String {
        switch error {
        case HandshakeError.rejected(.declined): String(localized: "The Mac said no.")
        case HandshakeError.rejected(.busy): String(localized: "The Mac is busy pairing with something else.")
        case HandshakeError.rejected(.unsupportedVersion): String(localized: "Update BetterDrop on both devices.")
        case HandshakeError.authenticationFailed: String(localized: "The codes didn't match. Try again.")
        default: String(localized: "Couldn't reach the Mac. Are you on the same Wi-Fi?")
        }
    }
}

extension PhoneModel.Pairing {
    var isFailure: Bool { if case .failed = self { true } else { false } }
}
