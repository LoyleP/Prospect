// Local/KeyVault.swift
// Where an event's private key lives: the organizer's Keychain, never leaving that phone.
// Whoever holds it can read the handovers; nobody else, including the developer, can.
import CryptoKit
import Foundation
import KeychainAccess

protocol KeyVault: Sendable {
    func privateKey(for event: UUID) -> Curve25519.KeyAgreement.PrivateKey?
    func store(_ key: Curve25519.KeyAgreement.PrivateKey, for event: UUID)
    func remove(for event: UUID)
}

final class KeychainKeyVault: KeyVault, @unchecked Sendable {
    private let keychain = Keychain(service: "com.flow.prospect.event-keys")
        .accessibility(.afterFirstUnlockThisDeviceOnly)

    func privateKey(for event: UUID) -> Curve25519.KeyAgreement.PrivateKey? {
        guard let data = try? keychain.getData(event.uuidString) else { return nil }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    func store(_ key: Curve25519.KeyAgreement.PrivateKey, for event: UUID) {
        try? keychain.set(key.rawRepresentation, key: event.uuidString)
    }

    func remove(for event: UUID) { try? keychain.remove(event.uuidString) }
}

/// For tests and demo data.
final class MemoryKeyVault: KeyVault, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [UUID: Curve25519.KeyAgreement.PrivateKey] = [:]

    func privateKey(for event: UUID) -> Curve25519.KeyAgreement.PrivateKey? {
        lock.lock(); defer { lock.unlock() }
        return keys[event]
    }
    func store(_ key: Curve25519.KeyAgreement.PrivateKey, for event: UUID) {
        lock.lock(); defer { lock.unlock() }
        keys[event] = key
    }
    func remove(for event: UUID) {
        lock.lock(); defer { lock.unlock() }
        keys[event] = nil
    }
}
