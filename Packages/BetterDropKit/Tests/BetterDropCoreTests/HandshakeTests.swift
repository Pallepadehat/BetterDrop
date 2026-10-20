import CryptoKit
import Foundation
import Testing
@testable import BetterDropCore

struct HandshakeTests {
    let phone = DeviceInfo(id: .random(), name: "Patrick's iPhone", kind: .iPhone)
    let mac = DeviceInfo(id: .random(), name: "Patrick's MacBook Pro", kind: .mac)

    /// Pairs the two through the wire format, the way the apps do.
    func pair() throws -> (phoneSide: PairedDevice, macSide: PairedDevice, phoneCode: String, macCode: String) {
        let initiator = PairingInitiator(device: phone)
        guard case let .pairRequest(request) = try HandshakeRecord.decode(HandshakeRecord.pairRequest(initiator.request).encoded())
        else { throw HandshakeError.unexpected }
        let responder = try PairingResponder(device: mac, request: request)
        let phoneAgreement = try initiator.agree(with: responder.challenge)
        #expect(phoneAgreement.checkProof(responder.agreement.acceptance().proof))
        return (phoneAgreement.paired(), responder.agreement.paired(), phoneAgreement.code, responder.agreement.code)
    }

    @Test func pairingShowsTheSameCodeOnBothScreens() throws {
        let result = try pair()
        #expect(result.phoneCode == result.macCode)
        #expect(result.phoneCode.count == 6)
        #expect(result.phoneCode.allSatisfy { $0.isNumber })
        #expect(result.phoneSide.secret == result.macSide.secret)
        #expect(result.phoneSide.device == mac)
        #expect(result.macSide.device == phone)
    }

    @Test func aManInTheMiddleSeesADifferentCode() throws {
        // Someone answers the phone's request with their own key, and opens their own pairing with the Mac.
        let initiator = PairingInitiator(device: phone)
        let attacker = try PairingResponder(device: mac, request: initiator.request)
        let phoneAgreement = try initiator.agree(with: attacker.challenge)
        let attackerToMac = PairingInitiator(device: phone)
        let macSide = try PairingResponder(device: mac, request: attackerToMac.request)
        #expect(phoneAgreement.code != macSide.agreement.code)
        #expect(!phoneAgreement.checkProof(macSide.agreement.acceptance().proof))
    }

    @Test func sessionsAgreeOnKeysAndEncryptBothWays() throws {
        let pairing = try pair()
        let initiator = SessionInitiator(device: phone, pairing: pairing.phoneSide)
        let responder = try SessionResponder(device: mac, hello: initiator.hello, pairing: pairing.macSide)
        let (finish, phoneKeys, peer) = try initiator.finish(with: responder.reply)
        let macKeys = try responder.verify(finish)
        #expect(peer == mac)

        var phoneSession = SecureSession(keys: phoneKeys)
        var macSession = SecureSession(keys: macKeys)
        for text in ["hello", "", String(repeating: "walrus ", count: 1000)] {
            #expect(try macSession.open(phoneSession.seal(Data(text.utf8))) == Data(text.utf8))
            #expect(try phoneSession.open(macSession.seal(Data(text.utf8))) == Data(text.utf8))
        }
    }

    @Test func aStrangerCantStartASession() throws {
        let pairing = try pair()
        let stranger = PairedDevice(device: mac, secret: Data(repeating: 0, count: 32))
        let initiator = SessionInitiator(device: phone, pairing: stranger)
        let responder = try SessionResponder(device: mac, hello: initiator.hello, pairing: pairing.macSide)
        #expect(throws: HandshakeError.authenticationFailed) { try initiator.finish(with: responder.reply) }

        // And a phone that doesn't know the secret can't finish.
        let honest = SessionInitiator(device: phone, pairing: pairing.phoneSide)
        let macSide = try SessionResponder(device: mac, hello: honest.hello, pairing: pairing.macSide)
        #expect(throws: HandshakeError.authenticationFailed) { try macSide.verify(ClientFinish(mac: Data(repeating: 1, count: 32))) }
    }

    @Test func theServerMustBeWhoWeExpect() throws {
        let pairing = try pair()
        let initiator = SessionInitiator(device: phone, pairing: pairing.phoneSide)
        let impostor = DeviceInfo(id: .random(), name: mac.name, kind: .mac)
        let responder = try SessionResponder(device: impostor, hello: initiator.hello, pairing: pairing.macSide)
        #expect(throws: HandshakeError.wrongDevice) { try initiator.finish(with: responder.reply) }
    }

    @Test func replayedOrTamperedRecordsFail() throws {
        let key = SymmetricKey(size: .bits256)
        let other = SymmetricKey(size: .bits256)
        var sender = SecureSession(keys: SessionKeys(sending: key, receiving: other))
        var receiver = SecureSession(keys: SessionKeys(sending: other, receiving: key))

        let first = try sender.seal(Data("one".utf8))
        let second = try sender.seal(Data("two".utf8))
        #expect(try receiver.open(first) == Data("one".utf8))
        #expect(throws: (any Error).self) { try receiver.open(first) }       // replayed

        var tampered = second
        tampered[tampered.startIndex] ^= 1
        var fresh = SecureSession(keys: SessionKeys(sending: other, receiving: key))
        _ = try fresh.open(first)
        #expect(throws: (any Error).self) { try fresh.open(tampered) }       // flipped a bit
    }

    @Test func storesRememberPairings() throws {
        let store = MemoryPairingStore()
        let paired = try pair().macSide
        try store.save(paired)
        #expect(store.pairing(for: phone.id) == paired)
        try store.remove(phone.id)
        #expect(store.all().isEmpty)

        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/pairings.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let file = FilePairingStore(url: url)
        try file.save(paired)
        #expect(FilePairingStore(url: url).all() == [paired])
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }
}
