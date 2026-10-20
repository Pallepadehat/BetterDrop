import BetterDropCore
import BetterDropTransport
import Foundation
import Observation
import os
import Photos
import SwiftUI
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

        var isFailure: Bool { if case .failed = self { true } else { false } }
    }

    let library: DropLibrary
    let browser: DeviceBrowser
    let scanner = ProximityScanner()
    private(set) var device: DeviceInfo
    private(set) var pairedMac: PairedDevice?
    private(set) var connection = Connection.idle
    private(set) var pairing = Pairing.idle
    private(set) var transfers: [UUID: Transfer] = [:]
    /// Which edge of this screen faces the Mac. The Mac says which side of it we're on; until it does, the left,
    /// as most people hold the phone to the right of a laptop.
    private(set) var macEdge = HorizontalEdge.leading
    /// Bumped for each burst of light: we connected, or something arrived or left.
    private(set) var surges = 0
    /// Bumped as files arrive and leave, for haptics.
    private(set) var arrivals = 0
    private(set) var departures = 0
    /// Items that just arrived, which condense out of light when they first appear.
    var freshItems: Set<UUID> = []
    /// How far a card being dragged has been pulled towards the Mac, 0 to 1: the edge glows to meet it.
    var dragPull: Double = 0
    var lastError: String?

    @ObservationIgnored private let store = Services.pairings
    @ObservationIgnored private let background = Services.background
    @ObservationIgnored private var link: PeerLink?
    @ObservationIgnored private var fileServer: FileServerAddress?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let log = Logger(subsystem: "BetterDrop", category: "phone")
    @ObservationIgnored private static let nameKey = "deviceName"

    init() {
        library = (try? DropLibrary(directory: URL.documentsDirectory))
            ?? (try! DropLibrary(directory: URL.applicationSupportDirectory.appending(path: "Library")))
        let id = LocalDevice.id()
        let name = UserDefaults.standard.string(forKey: Self.nameKey) ?? UIDevice.current.name
        device = DeviceInfo(id: id, name: name, kind: UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone)
        browser = DeviceBrowser(ignoring: id)
        pairedMac = store.all().max { $0.pairedAt < $1.pairedAt }
        // Big files finish whether or not anyone's looking, so this listens from launch, always.
        Task { await followBackgroundTransfers() }
    }

    // MARK: - Running

    func resume() {
        browser.start()
        scanner.start()
        guard tasks.isEmpty else { return }
        tasks = [
            Task { await maintainConnection() },
            Task { await reportProximity() },
            Task { await reportCloseness() },
        ]
        library.refresh()
        #if DEBUG
        runDemo()
        #endif
    }

    func suspend() {
        scanner.stop()
        tasks.forEach { $0.cancel() }
        tasks = []
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

    /// Tells the Mac how close we are when the level changes, so it can light up.
    private func reportProximity() async {
        let changes = Observations { [weak self] in
            self.map { model in model.pairedMac.map { model.scanner.proximity(of: $0.id) } ?? .away }
        }
        for await proximity in changes {
            guard let proximity, let link else { continue }
            try? await link.send(.proximity(proximity))
        }
    }

    /// And smoothly, at most fifteen times a second, for the Mac's light to follow the phone.
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

    // MARK: - Nearness

    /// The Mac to pair with: the one you're holding the phone to, or failing that, the only one around.
    var candidateMac: DiscoveredDevice? {
        let devices = browser.devices
        return devices.max { scanner.closeness(of: $0.id) < scanner.closeness(of: $1.id) } ?? devices.first
    }

    func proximity(of mac: DiscoveredDevice) -> Proximity { scanner.proximity(of: mac.id) }
    func closeness(of mac: DiscoveredDevice) -> Double { scanner.closeness(of: mac.id) }

    /// How close the paired Mac is, 0 to 1.
    var closeness: Double { pairedMac.map { scanner.closeness(of: $0.id) } ?? 0 }

    /// Bluetooth tells us how close the Mac is; without it (the Simulator, Bluetooth off) the light just stays on.
    var measuresProximity: Bool { scanner.availability == .available }

    /// How bright the edge of the screen is in the library.
    var edgeIntensity: Double {
        if transfers.values.contains(where: { $0.direction == .incoming }) { return 0.7 }
        if !transfers.isEmpty { return 0.45 }
        let near = connection == .connected ? max(0, (closeness - 0.45) / 0.55) * 0.5 : 0
        return max(near, dragPull * 0.9)
    }

    // MARK: - Pairing

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
            let (channel, peer) = try await ClientHandshake.startSession(over: connection, as: device, with: paired)
            pairedMac = paired
            attach(PeerLink(channel: channel, peer: peer))
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
        fileServer = nil
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
            attach(PeerLink(channel: channel, peer: peer))
        } catch HandshakeError.rejected(.unknownDevice) {
            framed.cancel()
            log.notice("The Mac doesn't know us any more; pairing again")
            forgetMac()
        } catch {
            framed.cancel()
            connection = .idle
        }
    }

    private func attach(_ link: PeerLink) {
        self.link?.closeSoon()
        self.link = link
        connection = .connected
        surges += 1
        if var paired = pairedMac, paired.device.name != link.peer.name {
            paired.device = link.peer
            try? store.save(paired)
            pairedMac = paired
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

    private func handle(_ event: LinkEvent, from link: PeerLink) {
        switch event {
        case let .incomingStarted(offer):
            transfers[offer.id] = Transfer(offer: offer, direction: .incoming, peerName: link.peer.name)
            surges += 1
        case let .progress(id, completed):
            transfers[id]?.completed = completed
        case let .incomingFinished(offer, url):
            Task { await keep(url, offer: offer, from: link.peer.name) }
        case let .outgoingFinished(id):
            transfers[id] = nil
        case let .failed(id, reason):
            fail(id, reason: reason)
        case let .side(side):
            macEdge = side == .right ? .leading : .trailing
        case let .fileServer(address):
            fileServer = address
        case let .backgroundOffer(offered):
            guard let pairedMac, let server = serverURL(for: link) else { return }
            transfers[offered.offer.id] = Transfer(offer: offered.offer, direction: .incoming, peerName: link.peer.name)
            surges += 1
            background.download(offered, pairing: pairedMac, as: device.id, from: server)
        case let .renamed(name):
            if var paired = pairedMac {
                paired.device.name = name
                try? store.save(paired)
                pairedMac = paired
            }
        case .proximity, .closeness:
            break
        case .closed:
            // Big files carry on without the connection; only the ones that were going over it are lost.
            for (id, transfer) in transfers where transfer.peerName == link.peer.name && !BackgroundProtocol.shouldUseBackground(for: transfer.byteCount) {
                transfers[id] = nil
            }
        }
    }

    private func serverURL(for link: PeerLink) -> URL? {
        fileServer.flatMap { BackgroundProtocol.baseURL(for: $0, preferring: link.remoteHost) }
    }

    private func followBackgroundTransfers() async {
        for await event in background.events {
            switch event {
            case let .progress(id, completed):
                transfers[id]?.completed = completed
            case let .uploaded(id):
                transfers[id] = nil
            case let .downloaded(offer, url, _):
                await keep(url, offer: offer, from: pairedMac?.device.name ?? "Mac")
            case let .failed(id, reason):
                fail(id, reason: reason)
            }
        }
    }

    private func keep(_ url: URL, offer: FileOffer, from peerName: String) async {
        do {
            let item = try await library.add(fileAt: url, named: offer.name, origin: .received(from: peerName), move: true)
            freshItems.insert(item.id)
            arrivals += 1
            surges += 1
        } catch {
            lastError = error.localizedDescription
        }
        transfers[offer.id] = nil
    }

    private func fail(_ id: UUID, reason: String) {
        if let transfer = transfers.removeValue(forKey: id) {
            lastError = String(localized: "\(transfer.name) didn't make it: \(reason)")
        }
    }

    // MARK: - Files

    var isConnected: Bool { connection == .connected }

    /// Files moving in the background right now, for the "you can leave the app" hint.
    var backgroundTransferCount: Int {
        transfers.values.filter { BackgroundProtocol.shouldUseBackground(for: $0.byteCount) }.count
    }

    func send(_ item: DropItem) {
        guard let link, let pairedMac else {
            lastError = String(localized: "Your Mac isn't connected. Open BetterDrop on it, on the same Wi-Fi.")
            return
        }
        let offer = FileOffer(item)
        let url = library.url(for: item)
        transfers[offer.id] = Transfer(offer: offer, direction: .outgoing, peerName: link.peer.name, itemID: item.id)
        departures += 1
        surges += 1
        Task {
            do {
                if BackgroundProtocol.shouldUseBackground(for: item.byteCount), let server = serverURL(for: link) {
                    // Finishes in the background: the transfer is cleared when the upload event arrives.
                    try await background.upload(fileAt: url, as: offer, pairing: pairedMac, from: device.id, to: server)
                    return
                }
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

    var incoming: [Transfer] {
        transfers.values.filter { $0.direction == .incoming }.sorted { $0.name < $1.name }
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
