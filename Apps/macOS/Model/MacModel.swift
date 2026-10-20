import AppKit
import BetterDropCore
import BetterDropTransport
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
    /// How close each phone is, 0 to 1, as it streams it.
    private(set) var closenesses: [DeviceID: Double] = [:]
    /// Bumped for every surge of light: a phone connected, or a file arrived or left.
    private(set) var surges = 0
    /// A phone asking to pair, waiting for you.
    private(set) var pendingApproval: PairingApproval?
    /// Files that just arrived, for the overlay to bring in out of the light. The overlay removes them once landed.
    var arrivals: [DropItem] = []
    /// Files are being dragged onto the edge.
    var isDropTargeted = false
    private(set) var lastError: String?

    @ObservationIgnored private let store: any PairingStore
    @ObservationIgnored private var links: [DeviceID: PeerLink] = [:]
    @ObservationIgnored private var advertiser: DeviceAdvertiser?
    @ObservationIgnored private var beacon: ProximityBeacon?
    @ObservationIgnored private var fileServer: FileServer?
    @ObservationIgnored private var approvalContinuation: CheckedContinuation<Bool, Never>?
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
        PeerLink.clearInbox()
        let advertiser = DeviceAdvertiser(device: device) { [weak self] connection in
            self?.accept(connection)
        }
        advertiser.start()
        self.advertiser = advertiser
        let beacon = ProximityBeacon(device: device.id)
        beacon.start()
        self.beacon = beacon
        Task { await startFileServer() }
    }

    private func startFileServer() async {
        do {
            let server = try FileServer(store: store)
            _ = try await server.start()
            fileServer = server
            for link in links.values { await announceFileServer(to: link) }
            for await event in server.events { handle(event) }
        } catch {
            log.error("No file server, so big files go the slow way: \(error.localizedDescription, privacy: .public)")
        }
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != device.name else { return }
        preferences.deviceName = trimmed
        device.name = trimmed
        advertiser?.rename(trimmed)
        broadcast(.rename(trimmed))
    }

    func sideChanged() {
        broadcast(.side(preferences.side))
    }

    private func broadcast(_ message: Message) {
        for link in links.values {
            Task { try? await link.send(message) }
        }
    }

    // MARK: - The light

    /// The nearest phone's closeness, 0 to 1.
    var closeness: Double { closenesses.values.max() ?? 0 }

    /// How bright the light at the edge of the screen is, 0 to 1.
    var portalIntensity: Double {
        if isDropTargeted { return 0.95 }
        if transfers.values.contains(where: { $0.direction == .incoming }) { return 0.8 }
        if pendingApproval != nil { return 0.7 }
        if !transfers.isEmpty { return 0.55 }
        // Grows smoothly as the phone comes closer, from nothing at arm's length to a steady glow touching.
        return max(0, (closeness - 0.35) / 0.65) * 0.55
    }

    /// Rings rolling out of the edge while a phone is close or something's on its way.
    var portalWaves: Double {
        if isDropTargeted || !transfers.isEmpty { return 1 }
        return max(0, (closeness - 0.3) / 0.7)
    }

    var isConnected: Bool { !connected.isEmpty }

    /// The phone files go to: the one that connected most recently.
    var currentPhone: DeviceInfo? { connected.first }

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
        surges += 1
        let answer = await withCheckedContinuation { continuation in
            pendingApproval = approval
            approvalContinuation = continuation
            #if DEBUG
            runDemoOnPairingRequest()
            #endif
            // Nobody at the Mac: say no after a minute rather than leave the phone hanging.
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
                attach(PeerLink(channel: channel, peer: peer))
            } catch {
                log.info("Connection from \(connection.remoteDescription, privacy: .public) ended: \(String(describing: error), privacy: .public)")
                connection.cancel()
            }
        }
    }

    private func attach(_ link: PeerLink) {
        let peer = link.peer
        links[peer.id]?.closeSoon()
        links[peer.id] = link
        connected.removeAll { $0.id == peer.id }
        connected.insert(peer, at: 0)
        pairedDevices = store.all()
        surges += 1
        if preferences.playsSounds { NSSound(named: "Pop")?.play() }
        #if DEBUG
        runDemoOnConnect()
        #endif

        let side = preferences.side
        Task {
            await link.start()
            try? await link.send(.side(side))
            await announceFileServer(to: link)
            for await event in link.events {
                handle(event, from: link)
            }
            // Only forget it if it hasn't been replaced by a newer connection from the same phone.
            if links[peer.id] === link {
                links[peer.id] = nil
                connected.removeAll { $0.id == peer.id }
                closenesses[peer.id] = nil
            }
        }
    }

    private func announceFileServer(to link: PeerLink) async {
        guard let port = fileServer?.port else { return }
        try? await link.send(.fileServer(FileServerAddress(port: port, hosts: LocalAddresses.ipv4())))
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
        case let .proximity(proximity):
            if proximity == .away { closenesses[link.peer.id] = 0 }
        case let .closeness(value):
            closenesses[link.peer.id] = value
        case let .renamed(name):
            if let index = connected.firstIndex(where: { $0.id == link.peer.id }) { connected[index].name = name }
        case .side, .fileServer, .backgroundOffer:
            break
        case .closed:
            for (id, transfer) in transfers where transfer.peerName == link.peer.name
                && !BackgroundProtocol.shouldUseBackground(for: transfer.byteCount) {
                transfers[id] = nil
            }
        }
    }

    private func handle(_ event: FileServerEvent) {
        switch event {
        case let .incomingStarted(offer, from):
            transfers[offer.id] = Transfer(offer: offer, direction: .incoming, peerName: name(of: from))
            surges += 1
        case let .progress(id, completed):
            transfers[id]?.completed = completed
        case let .received(offer, url, from):
            let name = name(of: from)
            Task { await keep(url, offer: offer, from: name) }
        case let .sent(id):
            transfers[id] = nil
            if preferences.playsSounds { NSSound(named: "Submarine")?.play() }
        case let .failed(id, reason):
            fail(id, reason: reason)
        }
    }

    private func name(of id: DeviceID) -> String {
        pairedDevices.first { $0.id == id }?.device.name ?? String(localized: "iPhone")
    }

    private func keep(_ url: URL, offer: FileOffer, from peerName: String) async {
        do {
            let item = try await library.add(fileAt: url, named: offer.name, origin: .received(from: peerName), move: true)
            arrivals.append(item)
            surges += 1
            if preferences.playsSounds { NSSound(named: "Glass")?.play() }
            if preferences.revealReceivedFiles { NSWorkspace.shared.activateFileViewerSelecting([library.url(for: item)]) }
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

    // MARK: - Sending

    /// Sends files to the phone, adding them to the library first so they show up on both sides.
    func send(_ urls: [URL]) {
        guard isConnected else {
            lastError = String(localized: "Connect your iPhone first: open BetterDrop on it and hold it next to your Mac.")
            return
        }
        Task {
            for url in urls {
                if let existing = library.items.first(where: { library.url(for: $0).standardizedFileURL == url.standardizedFileURL }) {
                    send(existing)
                } else if let added = try? await library.add(fileAt: url) {
                    send(added)
                }
            }
        }
    }

    func send(_ item: DropItem) {
        guard let phone = currentPhone, let link = links[phone.id] else { return }
        let offer = FileOffer(item)
        let url = library.url(for: item)
        transfers[offer.id] = Transfer(offer: offer, direction: .outgoing, peerName: link.peer.name, itemID: item.id)
        surges += 1

        // Big files are offered for the phone to fetch in the background: it keeps going if you leave the app.
        if BackgroundProtocol.shouldUseBackground(for: item.byteCount), let server = fileServer,
           let pairing = store.pairing(for: phone.id) {
            let offered = server.offer(fileAt: url, as: offer, to: pairing)
            Task {
                do {
                    try await link.send(.backgroundOffer(offered))
                } catch {
                    server.withdraw(offer.id)
                    fail(offer.id, reason: error.localizedDescription)
                }
            }
            return
        }
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

    func progress(for item: DropItem) -> Double? {
        transfers.values.first { $0.itemID == item.id }?.fraction
    }

    var incoming: [Transfer] {
        transfers.values.filter { $0.direction == .incoming }.sorted { $0.name < $1.name }
    }

    func dismissError() { lastError = nil }
}
