import BetterDropCore
import Foundation
import Network
import Observation

/// A Mac found on the network.
public struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    public let info: DeviceInfo
    public let endpoint: NWEndpoint

    public var id: DeviceID { info.id }
}

/// Finds Macs running BetterDrop with Bonjour, over Wi-Fi and peer-to-peer.
@MainActor
@Observable
public final class DeviceBrowser {
    public private(set) var devices: [DiscoveredDevice] = []
    /// Set when the local network is off limits (the permission was declined) or the browser broke.
    public private(set) var problem: String?

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private let ownID: DeviceID

    public init(ignoring ownID: DeviceID) {
        self.ownID = ownID
    }

    public func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: NetworkConfiguration.serviceType, domain: nil),
                                using: NetworkConfiguration.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap(Self.device(from:))
            Task { @MainActor in self?.update(found) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            let problem: String? = switch state {
            case let .failed(error), let .waiting(error): error.localizedDescription
            default: nil
            }
            Task { @MainActor in
                guard let self else { return }
                self.problem = problem
                if case .failed = state { self.restart() }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        devices = []
    }

    private func restart() {
        stop()
        Task {
            try? await Task.sleep(for: .seconds(2))
            start()
        }
    }

    private func update(_ found: [DiscoveredDevice]) {
        // One entry per device: a Mac on Wi-Fi and peer-to-peer at once shows up twice.
        var seen = Set<DeviceID>()
        devices = found
            .filter { $0.id != ownID && seen.insert($0.id).inserted }
            .sorted { $0.info.name.localizedStandardCompare($1.info.name) == .orderedAscending }
    }

    private nonisolated static func device(from result: NWBrowser.Result) -> DiscoveredDevice? {
        guard case let .bonjour(txt) = result.metadata,
              let id = txt[BonjourKey.id], !id.isEmpty,
              txt[BonjourKey.version] == String(HandshakeRecord.protocolVersion)
        else { return nil }
        let serviceName: String? = if case let .service(name, _, _, _) = result.endpoint { name } else { nil }
        let name = txt[BonjourKey.name] ?? serviceName ?? "Mac"
        let kind = txt[BonjourKey.kind].flatMap(DeviceKind.init(rawValue:)) ?? .mac
        return DiscoveredDevice(info: DeviceInfo(id: DeviceID(rawValue: id), name: name, kind: kind), endpoint: result.endpoint)
    }
}
