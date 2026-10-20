import BetterDropCore
import Foundation
import Network
import Observation
import os

/// Listens for phones and tells the network about this Mac with Bonjour. Each phone that connects is handed to
/// `onConnection` as a ``FramedConnection``, ready for ``ServerHandshake/accept(_:as:store:approve:)``.
@MainActor
@Observable
public final class DeviceAdvertiser {
    public enum State: Equatable, Sendable {
        case stopped
        case starting
        case advertising(port: UInt16)
        case failed(String)
    }

    public private(set) var state: State = .stopped

    @ObservationIgnored private var device: DeviceInfo
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private let onConnection: @MainActor (FramedConnection) -> Void
    @ObservationIgnored private let queue = DispatchQueue(label: "BetterDrop.listener")
    @ObservationIgnored private let fixedPort: NWEndpoint.Port
    @ObservationIgnored private let advertises: Bool

    /// `advertises: false` and a `port` are for tests, which connect straight to localhost.
    public init(device: DeviceInfo, port: NWEndpoint.Port = .any, advertises: Bool = true,
                onConnection: @escaping @MainActor (FramedConnection) -> Void) {
        self.device = device
        self.onConnection = onConnection
        fixedPort = port
        self.advertises = advertises
    }

    public func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: NetworkConfiguration.parameters(), on: fixedPort)
            if advertises { listener.service = service() }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.update(state, port: listener.port?.rawValue) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.onConnection(FramedConnection(connection)) }
            }
            state = .starting
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        state = .stopped
    }

    /// Changes the name other devices see.
    public func rename(_ name: String) {
        device.name = name
        if advertises { listener?.service = service() }
    }

    private func service() -> NWListener.Service {
        var txt = NWTXTRecord()
        txt[BonjourKey.id] = device.id.rawValue
        txt[BonjourKey.name] = device.name
        txt[BonjourKey.kind] = device.kind.rawValue
        txt[BonjourKey.version] = String(HandshakeRecord.protocolVersion)
        return NWListener.Service(name: device.name, type: NetworkConfiguration.serviceType, txtRecord: txt)
    }

    private func update(_ newState: NWListener.State, port: UInt16?) {
        switch newState {
        case .ready: state = .advertising(port: port ?? 0)
        case let .failed(error):
            Log.network.error("Listener failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            // Wi-Fi coming back, waking from sleep: start again.
            listener?.cancel()
            listener = nil
            Task {
                try? await Task.sleep(for: .seconds(2))
                start()
            }
        case .cancelled: state = .stopped
        default: break
        }
    }
}

enum BonjourKey {
    static let id = "id"
    static let name = "name"
    static let kind = "kind"
    static let version = "v"
}

enum Log {
    static let network = Logger(subsystem: "BetterDrop", category: "network")
    static let proximity = Logger(subsystem: "BetterDrop", category: "proximity")
}
