import AppKit
import BetterDropCore
import BetterDropTransport
import BetterDropUI
import Observation
import os

/// Everything the Mac app knows: the library, the phones that are paired and connected, files on the move, and how
/// bright the edge of the screen should be.
@Observable
final class MacModel {
    let preferences = Preferences()
    let library: DropLibrary
    private(set) var device: DeviceInfo

    private(set) var pairedDevices: [PairedDevice] = []
    /// Phones connected right now, newest first.
    private(set) var connected: [DeviceInfo] = []
    private(set) var transfers: [UUID: Transfer] = [:]
    private(set) var proximities: [DeviceID: Proximity] = [:]
    /// How close each phone is, 0 to 1, as it streams it.
    private(set) var closenesses: [DeviceID: Double] = [:]
    /// Bumped for every shockwave: a phone connected, or a file arrived or left.
    private(set) var bursts = 0
    /// A phone asking to pair, waiting for you.
    private(set) var pendingApproval: PairingApproval?
    /// Files that just arrived, for the overlay to fly in. Removed by the overlay once they've landed.
    var arrivals: [DropItem] = []
    /// The edge is being dragged onto.
    var isDropTargeted = false
    /// A short burst of light when something arrives or leaves.
    private(set) var flash = false
    private(set) var lastError: String?

    @ObservationIgnored private let store: any PairingStore
    @ObservationIgnored private var links: [DeviceID: Link] = [:]
    @ObservationIgnored private var advertiser: DeviceAdvertiser?
    @ObservationIgnored private var beacon: ProximityBeacon?
    @ObservationIgnored private var approvalContinuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "BetterDrop", category: "mac")

    init() {
        let downloads = URL.downloadsDirectory.appending(path: "BetterDrop", directoryHint: .isDirectory)
        // If ~/Downloads can't be written to, fall back to Application Support rather than not starting at all.
        library = (try? DropLibrary(directory: downloads))
            ?? (try! DropLibrary(directory: URL.applicationSupportDirectory.appending(path: "BetterDrop/Library")))
        store = FilePairingStore(url: URL.applicationSupportDirectory.appending(path: "BetterDrop/pairings.json"))
        device = DeviceInfo(id: LocalDevice.id(), name: preferences.deviceName, kind: .mac)
        pairedDevices = store.all()
    }

    // MARK: - Starting

    func start() {
        Link.clearInbox()
        let advertiser = DeviceAdvertiser(device: device) { [weak self] connection in
            self?.accept(connection)
        }
        advertiser.start()
        self.advertiser = advertiser
        let beacon = ProximityBeacon(device: device.id)
        beacon.start()
        self.beacon = beacon
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != device.name else { return }
        preferences.deviceName = trimmed
        device.name = trimmed
        advertiser?.rename(trimmed)
        for link in links.values {
            Task { try? await link.send(.rename(trimmed)) }
        }
    }

    // MARK: - The edge's light

    /// How bright the bloom at the edge of the screen is, from 0 to 1.
    var bloomIntensity: Double {
        if flash || isDropTargeted || transfers.values.contains(where: { $0.direction == .incoming }) { return 1 }
        if pendingApproval != nil { return 0.75 }
        if !transfers.isEmpty { return 0.7 }
        // Grows smoothly as the phone comes closer, from nothing at arm's length to a steady glow touching.
        return max(0, (closeness - 0.35) / 0.65) * 0.5
    }

    /// The nearest phone's closeness, 0 to 1.
    var closeness: Double { closenesses.values.max() ?? 0 }

    /// Sonar rolling out of the edge while a phone is close.
    var waveIntensity: Double { max(0, (closeness - 0.3) / 0.7) }

    /// Which side of the Mac the phone sits on, as the phone sees it.
    var phoneSide: Side { preferences.edge == .trailing ? .right : .left }

    func edgeChanged() {
        for link in links.values {
            Task { try? await link.send(.side(phoneSide)) }
        }
    }

    var isConnected: Bool { !connected.isEmpty }

    /// The phone that files go to: the one that connected most recently.
    var currentPhone: DeviceInfo? { connected.first }

    private func flashOnce() {
        flashTask?.cancel()
        flash = true
        flashTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            flash = false
        }
    }

    // MARK: - Pairing

    func answerPairing(_ accept: Bool) {
        approvalContinuation?.resume(returning: accept)
        approvalContinuation = nil
        pendingApproval = nil
    }

    func forget(_ paired: PairedDevice) {
        try? store.remove(paired.id)
        links[paired.id]?.closeSoon()
        pairedDevices = store.all()
    }

    /// Asks you about a new phone. One at a time; a second phone asking meanwhile is told no.
    private func approve(_ approval: PairingApproval) async -> Bool {
        guard pendingApproval == nil else { return false }
        NSApp.activate()
        let answer = await withCheckedContinuation { continuation in
            pendingApproval = approval
            approvalContinuation = continuation
            #if DEBUG
            runDemoOnPairingRequest()
            #endif
            // Nobody at the Mac: say no after a minute rather than hang the phone forever.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                if self?.pendingApproval?.id == approval.id { self?.answerPairing(false) }
            }
        }
        if answer { pairedDevices = store.all() }
        return answer
    }

    // MARK: - Connections

    private func accept(_ connection: FramedConnection) {
        let device = device, store = store
        Task {
            do {
                try await connection.start()
                let (channel, peer) = try await ServerHandshake.accept(connection, as: device, store: store) { [weak self] approval in
                    await self?.approve(approval) ?? false
                }
                attach(Link(channel: channel, peer: peer))
            } catch {
                log.info("Connection from \(connection.remoteDescription, privacy: .public) ended: \(String(describing: error), privacy: .public)")
                connection.cancel()
            }
        }
    }

    private func attach(_ link: Link) {
        let peer = link.peer
        links[peer.id]?.closeSoon()
        links[peer.id] = link
        connected.removeAll { $0.id == peer.id }
        connected.insert(peer, at: 0)
        pairedDevices = store.all()
        if preferences.playsSounds { NSSound(named: "Pop")?.play() }
        #if DEBUG
        runDemoOnConnect()
        #endif

        bursts += 1
        let side = phoneSide
        Task {
            await link.start()
            try? await link.send(.side(side))
            for await event in link.events {
                handle(event, from: link)
            }
            // Only forget it if it hasn't been replaced by a newer connection from the same phone.
            if links[peer.id] === link {
                links[peer.id] = nil
                connected.removeAll { $0.id == peer.id }
                proximities[peer.id] = nil
                closenesses[peer.id] = nil
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
            Task { await keep(url, offer: offer, from: link.peer) }
        case let .outgoingFinished(id):
            transfers[id] = nil
        case let .failed(id, reason):
            if let transfer = transfers.removeValue(forKey: id) {
                lastError = String(localized: "\(transfer.name) didn't make it: \(reason)")
            }
        case let .proximity(proximity):
            proximities[link.peer.id] = proximity
        case let .closeness(value):
            closenesses[link.peer.id] = value
        case .side:
            break
        case let .renamed(name):
            if let index = connected.firstIndex(where: { $0.id == link.peer.id }) { connected[index].name = name }
        case .closed:
            for (id, transfer) in transfers where transfer.peerName == link.peer.name { transfers[id] = nil }
        }
    }

    private func keep(_ url: URL, offer: FileOffer, from peer: DeviceInfo) async {
        do {
            let item = try await library.add(fileAt: url, named: offer.name, origin: .received(from: peer.name), move: true)
            transfers[offer.id] = nil
            arrivals.append(item)
            flashOnce()
            if preferences.playsSounds { NSSound(named: "Glass")?.play() }
            if preferences.revealReceivedFiles { NSWorkspace.shared.activateFileViewerSelecting([library.url(for: item)]) }
        } catch {
            transfers[offer.id] = nil
            lastError = error.localizedDescription
        }
    }

    // MARK: - Sending

    /// Sends files to the phone, adding them to the library first so they show up on both sides.
    func send(_ urls: [URL]) {
        guard let phone = currentPhone, let link = links[phone.id] else {
            lastError = String(localized: "Connect your iPhone first: open BetterDrop on it and hold it next to your Mac.")
            return
        }
        Task {
            for url in urls {
                // Files that are already in the library go as they are; anything else is copied in.
                let item: DropItem
                if let existing = library.items.first(where: { library.url(for: $0).standardizedFileURL == url.standardizedFileURL }) {
                    item = existing
                } else {
                    guard let added = try? await library.add(fileAt: url) else { continue }
                    item = added
                }
                send(item, over: link)
            }
        }
    }

    func send(_ item: DropItem) {
        guard let phone = currentPhone, let link = links[phone.id] else { return }
        send(item, over: link)
    }

    private func send(_ item: DropItem, over link: Link) {
        let offer = FileOffer(item)
        transfers[offer.id] = Transfer(offer: offer, direction: .outgoing, peerName: link.peer.name, itemID: item.id)
        bursts += 1
        flashOnce()
        let url = library.url(for: item)
        Task {
            do {
                try await link.send(fileAt: url, as: offer)
                if preferences.playsSounds { NSSound(named: "Submarine")?.play() }
            } catch {
                lastError = String(localized: "Couldn't send \(item.name): \(error.localizedDescription)")
            }
            transfers[offer.id] = nil
        }
    }

    func cancel(_ transfer: Transfer) {
        guard let link = links.values.first(where: { $0.peer.name == transfer.peerName }) else { return }
        Task { await link.cancel(transfer.id) }
        transfers[transfer.id] = nil
    }

    func progress(for item: DropItem) -> Double? {
        transfers.values.first { $0.itemID == item.id }?.fraction
    }

    func dismissError() { lastError = nil }
}
