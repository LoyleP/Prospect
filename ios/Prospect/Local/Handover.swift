// Local/Handover.swift
// The agent's end-of-day file. It is encrypted to the organizer's event key, so it can travel through
// AirDrop, Mail, a messaging app or a USB stick: only the organizer's phone can open it.
//
// Scheme: an ephemeral Curve25519 key per file, ECDH with the organizer's public key, HKDF-SHA256 with the
// event id as salt, AES-256-GCM with the event id as authenticated data.
import CryptoKit
import Foundation

enum Handover {
    static let fileExtension = "prospects"
    private static let info = Data("prospect-handover-v1".utf8)

    /// Clear-text metadata, so the app can pick the right event and key before decrypting.
    struct Envelope: Codable, Equatable, Sendable {
        var v = 1
        var event: UUID
        var agent: UUID
        var from: String
        var count: Int
        var epk: String      // ephemeral public key, base64
        var box: String      // AES-GCM combined (nonce + ciphertext + tag), base64
    }

    struct Payload: Codable, Equatable, Sendable {
        var agentId: UUID
        var agentName: String
        var sentAt: Date
        var prospects: [Prospect]
    }

    enum HandoverError: Error, Equatable {
        case notAHandover, wrongEvent, cannotDecrypt, badKey
    }

    static func seal(_ payload: Payload, eventId: UUID, organizerPublicKey: String) throws -> Data {
        guard let raw = Data(base64Encoded: organizerPublicKey),
              let organizerKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) else { throw HandoverError.badKey }
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let key = try symmetricKey(secret: ephemeral.sharedSecretFromKeyAgreement(with: organizerKey), eventId: eventId)
        let plaintext = try encoder.encode(payload)
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: eventIdData(eventId))
        let envelope = Envelope(
            event: eventId, agent: payload.agentId, from: payload.agentName, count: payload.prospects.count,
            epk: ephemeral.publicKey.rawRepresentation.base64EncodedString(),
            box: sealed.combined!.base64EncodedString()
        )
        return try encoder.encode(envelope)
    }

    /// Reads the clear-text part only (to find which event this file belongs to).
    static func envelope(of data: Data) -> Envelope? {
        try? decoder.decode(Envelope.self, from: data)
    }

    static func open(_ data: Data, privateKey: Curve25519.KeyAgreement.PrivateKey, eventId: UUID) throws -> (Envelope, Payload) {
        guard let envelope = envelope(of: data) else { throw HandoverError.notAHandover }
        guard envelope.event == eventId else { throw HandoverError.wrongEvent }
        guard let epkRaw = Data(base64Encoded: envelope.epk), let boxRaw = Data(base64Encoded: envelope.box),
              let ephemeral = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: epkRaw) else { throw HandoverError.notAHandover }
        do {
            let key = try symmetricKey(secret: privateKey.sharedSecretFromKeyAgreement(with: ephemeral), eventId: eventId)
            let box = try AES.GCM.SealedBox(combined: boxRaw)
            let plaintext = try AES.GCM.open(box, using: key, authenticating: eventIdData(eventId))
            return (envelope, try decoder.decode(Payload.self, from: plaintext))
        } catch {
            throw HandoverError.cannotDecrypt
        }
    }

    private static func symmetricKey(secret: SharedSecret, eventId: UUID) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: eventIdData(eventId), sharedInfo: info, outputByteCount: 32)
    }

    private static func eventIdData(_ id: UUID) -> Data {
        withUnsafeBytes(of: id.uuid) { Data($0) }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
