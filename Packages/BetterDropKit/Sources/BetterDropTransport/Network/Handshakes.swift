import BetterDropCore
import Foundation

/// A phone asking to pair, as the Mac shows it: who it is and the code to compare.
public struct PairingApproval: Sendable, Identifiable, Equatable {
    public let id = UUID()
    public let device: DeviceInfo
    public let code: String
}

/// The phone's side of a new connection.
public enum ClientHandshake {
    /// Pairs with the Mac. `showCode` is called as soon as the code is known, so the phone can show it while you
    /// look at the Mac and accept. Returns the pairing to keep; start a session with ``startSession(over:as:with:)``.
    public static func pair(over connection: FramedConnection, as device: DeviceInfo,
                            showCode: @Sendable (String) async -> Void) async throws -> PairedDevice {
        let initiator = PairingInitiator(device: device)
        try await connection.send(HandshakeRecord.pairRequest(initiator.request).encoded())
        guard case let .pairChallenge(challenge) = try await receive(connection) else { throw HandshakeError.unexpected }
        let agreement = try initiator.agree(with: challenge)
        await showCode(agreement.code)

        // Now someone has to walk over to the Mac.
        guard case let .pairResult(result) = try await receive(connection) else { throw HandshakeError.unexpected }
        guard result.accepted else { throw HandshakeError.rejected(.declined) }
        guard agreement.checkProof(result.proof) else { throw HandshakeError.authenticationFailed }
        return agreement.paired()
    }

    public static func startSession(over connection: FramedConnection, as device: DeviceInfo,
                                    with pairing: PairedDevice) async throws -> (channel: SecureChannel, peer: DeviceInfo) {
        let initiator = SessionInitiator(device: device, pairing: pairing)
        try await connection.send(HandshakeRecord.clientHello(initiator.hello).encoded())
        guard case let .serverHello(reply) = try await receive(connection) else { throw HandshakeError.unexpected }
        let (finish, keys, peer) = try initiator.finish(with: reply)
        try await connection.send(HandshakeRecord.clientFinish(finish).encoded())
        return (SecureChannel(connection: connection, keys: keys), peer)
    }
}

/// The Mac's side of a new connection.
public enum ServerHandshake {
    /// Runs whatever the phone asks for, pairing first if it wants to, and ends with an encrypted channel.
    /// `approve` is asked about new phones: return true once you've compared the codes.
    public static func accept(_ connection: FramedConnection, as device: DeviceInfo, store: any PairingStore,
                              approve: @Sendable (PairingApproval) async -> Bool) async throws -> (channel: SecureChannel, peer: DeviceInfo) {
        var record = try await receive(connection)

        if case let .pairRequest(request) = record {
            let responder: PairingResponder
            do {
                responder = try PairingResponder(device: device, request: request)
            } catch HandshakeError.rejected(let reason) {
                try? await connection.send(HandshakeRecord.rejected(reason).encoded())
                throw HandshakeError.rejected(reason)
            }
            try await connection.send(HandshakeRecord.pairChallenge(responder.challenge).encoded())
            guard await approve(PairingApproval(device: request.device, code: responder.agreement.code)) else {
                try? await connection.send(HandshakeRecord.pairResult(.declined).encoded())
                throw HandshakeError.rejected(.declined)
            }
            try store.save(responder.agreement.paired())
            try await connection.send(HandshakeRecord.pairResult(responder.agreement.acceptance()).encoded())
            record = try await receive(connection)
        }

        guard case let .clientHello(hello) = record else { throw HandshakeError.unexpected }
        guard hello.version == HandshakeRecord.protocolVersion else {
            try? await connection.send(HandshakeRecord.rejected(.unsupportedVersion).encoded())
            throw HandshakeError.rejected(.unsupportedVersion)
        }
        guard var pairing = store.pairing(for: hello.device.id) else {
            try? await connection.send(HandshakeRecord.rejected(.unknownDevice).encoded())
            throw HandshakeError.rejected(.unknownDevice)
        }
        let responder = try SessionResponder(device: device, hello: hello, pairing: pairing)
        try await connection.send(HandshakeRecord.serverHello(responder.reply).encoded())
        guard case let .clientFinish(finish) = try await receive(connection) else { throw HandshakeError.unexpected }
        let keys: SessionKeys
        do {
            keys = try responder.verify(finish)
        } catch {
            try? await connection.send(HandshakeRecord.rejected(.authenticationFailed).encoded())
            throw error
        }
        // Phones get renamed; remember the new name.
        if pairing.device != hello.device {
            pairing.device = hello.device
            try? store.save(pairing)
        }
        return (SecureChannel(connection: connection, keys: keys), hello.device)
    }
}

private func receive(_ connection: FramedConnection) async throws -> HandshakeRecord {
    let record = try HandshakeRecord.decode(try await connection.receive())
    if case let .rejected(reason) = record { throw HandshakeError.rejected(reason) }
    return record
}
