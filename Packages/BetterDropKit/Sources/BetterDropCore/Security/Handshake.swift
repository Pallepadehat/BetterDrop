import CryptoKit
import Foundation

/// The plaintext records sent before a connection is encrypted. The phone always starts (it found the Mac), with
/// either ``pairRequest`` (we've never met) or ``clientHello`` (we're paired, let's talk).
///
/// **Pairing** is an unauthenticated X25519 exchange. Both screens show a six-digit code made from the exchange; when
/// you accept on the Mac you're confirming the codes match, which proves nobody sat in the middle. Both sides then
/// keep a 256-bit pairing secret.
///
/// **Sessions** prove both sides hold that secret (HMAC over the whole exchange) and agree fresh ephemeral X25519
/// keys, so a leaked pairing secret can't decrypt an earlier recording.
public enum HandshakeRecord: Codable, Sendable, Equatable {
    case pairRequest(PairRequest)
    case pairChallenge(PairChallenge)
    case pairResult(PairResult)
    case clientHello(ClientHello)
    case serverHello(ServerHello)
    case clientFinish(ClientFinish)
    case rejected(Rejection)

    public static let protocolVersion = 1

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> HandshakeRecord { try JSONDecoder().decode(Self.self, from: data) }
}

public struct PairRequest: Codable, Sendable, Equatable {
    public var version: Int
    public var device: DeviceInfo
    public var publicKey: Data
}

public struct PairChallenge: Codable, Sendable, Equatable {
    public var device: DeviceInfo
    public var publicKey: Data
}

public struct PairResult: Codable, Sendable, Equatable {
    public var accepted: Bool
    /// Proves the Mac derived the same secret, so the phone knows the code it showed was the one that was accepted.
    public var proof: Data?
}

public struct ClientHello: Codable, Sendable, Equatable {
    public var version: Int
    public var device: DeviceInfo
    public var publicKey: Data
    public var nonce: Data
}

public struct ServerHello: Codable, Sendable, Equatable {
    public var device: DeviceInfo
    public var publicKey: Data
    public var nonce: Data
    public var mac: Data
}

public struct ClientFinish: Codable, Sendable, Equatable {
    public var mac: Data
}

public enum Rejection: String, Codable, Sendable, Error, Equatable {
    /// The Mac doesn't know this phone (it was forgotten, or never paired): pair again.
    case unknownDevice
    /// Someone said no on the Mac.
    case declined
    /// The other side speaks a newer protocol.
    case unsupportedVersion
    /// A proof didn't check out. Someone is in the middle, or the pairing is stale.
    case authenticationFailed
    /// The Mac is already pairing with someone else.
    case busy
}

public enum HandshakeError: Error, Equatable {
    case unexpected
    case badKey
    case authenticationFailed
    case wrongDevice
    case rejected(Rejection)
}

// MARK: - Pairing

/// The secret two devices share once they're paired, plus who the other one is.
public struct PairedDevice: Codable, Sendable, Hashable, Identifiable {
    public var device: DeviceInfo
    public var secret: Data
    public var pairedAt: Date

    public var id: DeviceID { device.id }

    public init(device: DeviceInfo, secret: Data, pairedAt: Date = .now) {
        self.device = device
        self.secret = secret
        self.pairedAt = pairedAt
    }
}

/// What both sides arrive at after the pairing exchange, before anyone has said yes.
public struct PairingAgreement: Sendable {
    /// The six digits both screens show, as a string so leading zeros survive.
    public let code: String
    public let peer: DeviceInfo
    let secret: SymmetricKey

    public func paired() -> PairedDevice {
        PairedDevice(device: peer, secret: secret.withUnsafeBytes { Data($0) })
    }

    func proof(_ label: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(label.utf8), using: secret))
    }

    public func checkProof(_ data: Data?) -> Bool {
        guard let data else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(data, authenticating: Data("pairing accepted".utf8), using: secret)
    }

    public func acceptance() -> PairResult { PairResult(accepted: true, proof: proof("pairing accepted")) }

    static func derive(shared: SharedSecret, initiator: PairRequest, responder: PairChallenge, peer: DeviceInfo) -> PairingAgreement {
        var transcript = SHA256()
        transcript.update(data: Data("BetterDrop pairing v\(HandshakeRecord.protocolVersion)".utf8))
        transcript.update(data: initiator.publicKey)
        transcript.update(data: responder.publicKey)
        transcript.update(data: Data(initiator.device.id.rawValue.utf8))
        transcript.update(data: Data(responder.device.id.rawValue.utf8))
        let salt = Data(transcript.finalize())

        let codeKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("code".utf8), outputByteCount: 8)
        let number = codeKey.withUnsafeBytes { UInt64(bigEndianData: $0) } % 1_000_000
        let secret = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("pairing secret".utf8), outputByteCount: 32)
        return PairingAgreement(code: String(format: "%06llu", number), peer: peer, secret: secret)
    }
}

/// The phone's half of pairing.
public struct PairingInitiator: Sendable {
    private let key = Curve25519.KeyAgreement.PrivateKey()
    public let request: PairRequest

    public init(device: DeviceInfo) {
        request = PairRequest(version: HandshakeRecord.protocolVersion, device: device, publicKey: key.publicKey.rawRepresentation)
    }

    public func agree(with challenge: PairChallenge) throws -> PairingAgreement {
        guard let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: challenge.publicKey) else { throw HandshakeError.badKey }
        let shared = try key.sharedSecretFromKeyAgreement(with: theirs)
        return .derive(shared: shared, initiator: request, responder: challenge, peer: challenge.device)
    }
}

/// The Mac's half of pairing.
public struct PairingResponder: Sendable {
    public let challenge: PairChallenge
    public let agreement: PairingAgreement

    public init(device: DeviceInfo, request: PairRequest) throws {
        guard request.version == HandshakeRecord.protocolVersion else { throw HandshakeError.rejected(.unsupportedVersion) }
        guard let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: request.publicKey) else { throw HandshakeError.badKey }
        let key = Curve25519.KeyAgreement.PrivateKey()
        challenge = PairChallenge(device: device, publicKey: key.publicKey.rawRepresentation)
        let shared = try key.sharedSecretFromKeyAgreement(with: theirs)
        agreement = .derive(shared: shared, initiator: request, responder: challenge, peer: request.device)
    }
}

// MARK: - Sessions

private enum SessionTranscript {
    static func hash(_ hello: ClientHello, _ server: (device: DeviceInfo, publicKey: Data, nonce: Data)) -> Data {
        var hash = SHA256()
        hash.update(data: Data("BetterDrop session v\(HandshakeRecord.protocolVersion)".utf8))
        hash.update(data: Data(hello.device.id.rawValue.utf8))
        hash.update(data: hello.publicKey)
        hash.update(data: hello.nonce)
        hash.update(data: Data(server.device.id.rawValue.utf8))
        hash.update(data: server.publicKey)
        hash.update(data: server.nonce)
        return Data(hash.finalize())
    }

    static func mac(_ label: String, transcript: Data, secret: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(label.utf8) + transcript, using: secret))
    }

    static func keys(shared: SharedSecret, secret: SymmetricKey, transcript: Data) -> (clientToServer: SymmetricKey, serverToClient: SymmetricKey) {
        let salt = secret.withUnsafeBytes { Data($0) }
        func key(_ label: String) -> SymmetricKey {
            shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data(label.utf8) + transcript, outputByteCount: 32)
        }
        return (key("client to server"), key("server to client"))
    }

    static func nonce() -> Data {
        Data(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }
}

/// The phone's half of starting a session with a paired Mac.
public struct SessionInitiator: Sendable {
    private let key = Curve25519.KeyAgreement.PrivateKey()
    private let pairing: PairedDevice
    public let hello: ClientHello

    public init(device: DeviceInfo, pairing: PairedDevice) {
        self.pairing = pairing
        hello = ClientHello(version: HandshakeRecord.protocolVersion, device: device,
                            publicKey: key.publicKey.rawRepresentation, nonce: SessionTranscript.nonce())
    }

    /// Checks the Mac proved it knows our secret, and returns what to send back and the keys to use from then on.
    public func finish(with server: ServerHello) throws -> (finish: ClientFinish, keys: SessionKeys, peer: DeviceInfo) {
        guard server.device.id == pairing.device.id else { throw HandshakeError.wrongDevice }
        let secret = SymmetricKey(data: pairing.secret)
        let transcript = SessionTranscript.hash(hello, (server.device, server.publicKey, server.nonce))
        let expected = SessionTranscript.mac("server", transcript: transcript, secret: secret)
        guard expected.constantTimeEquals(server.mac) else { throw HandshakeError.authenticationFailed }
        guard let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: server.publicKey) else { throw HandshakeError.badKey }
        let keys = SessionTranscript.keys(shared: try key.sharedSecretFromKeyAgreement(with: theirs), secret: secret, transcript: transcript)
        return (ClientFinish(mac: SessionTranscript.mac("client", transcript: transcript, secret: secret)),
                SessionKeys(sending: keys.clientToServer, receiving: keys.serverToClient),
                server.device)
    }
}

/// The Mac's half of starting a session with a paired phone.
public struct SessionResponder: Sendable {
    public let reply: ServerHello
    private let transcript: Data
    private let secret: SymmetricKey
    private let keys: SessionKeys

    public init(device: DeviceInfo, hello: ClientHello, pairing: PairedDevice) throws {
        guard hello.version == HandshakeRecord.protocolVersion else { throw HandshakeError.rejected(.unsupportedVersion) }
        guard hello.device.id == pairing.device.id else { throw HandshakeError.wrongDevice }
        guard let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: hello.publicKey) else { throw HandshakeError.badKey }
        let key = Curve25519.KeyAgreement.PrivateKey()
        let nonce = SessionTranscript.nonce()
        secret = SymmetricKey(data: pairing.secret)
        transcript = SessionTranscript.hash(hello, (device, key.publicKey.rawRepresentation, nonce))
        reply = ServerHello(device: device, publicKey: key.publicKey.rawRepresentation, nonce: nonce,
                            mac: SessionTranscript.mac("server", transcript: transcript, secret: secret))
        let derived = SessionTranscript.keys(shared: try key.sharedSecretFromKeyAgreement(with: theirs), secret: secret, transcript: transcript)
        keys = SessionKeys(sending: derived.serverToClient, receiving: derived.clientToServer)
    }

    /// Checks the phone proved it knows the secret too. Only then are the keys handed out.
    public func verify(_ finish: ClientFinish) throws -> SessionKeys {
        let expected = SessionTranscript.mac("client", transcript: transcript, secret: secret)
        guard expected.constantTimeEquals(finish.mac) else { throw HandshakeError.authenticationFailed }
        return keys
    }
}

extension Data {
    /// Compares without stopping at the first difference, so timing doesn't leak how much of a MAC was right.
    func constantTimeEquals(_ other: Data) -> Bool {
        guard count == other.count else { return false }
        return zip(self, other).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
