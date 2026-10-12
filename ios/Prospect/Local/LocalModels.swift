// Local/LocalModels.swift
// What a phone stores. There is no server: each event, with its prospects, lives here. The organizer's
// phone also holds the event's private key (in the Keychain, see KeyVault) and the handovers it received.
import Foundation

struct StoredIdentity: Codable, Equatable, Sendable {
    var displayName: String
    /// `.admin` = organizer (creates events, collects the agents' files); `.agent` = records and sends.
    var role: Role
    /// What this person calls events ("Événement", "JPO", "Salon"…).
    var eventLabel: String
}

/// One file received from an agent (organizer side).
struct HandoverReceipt: Codable, Identifiable, Equatable, Sendable {
    var id: UUID            // the agent's id
    var agentName: String
    var count: Int          // prospects in the latest file
    var added: Int          // how many of them were new when it was merged
    var receivedAt: Date
}

struct StoredEvent: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var date: String                    // "YYYY-MM-DD"
    var endsAt: Date?                   // when agents are reminded to send their prospects
    var status: SessionStatut
    var isArchived: Bool
    var preRegistered: Int
    var rdvTargetLow: Int
    var rdvTargetHigh: Int
    var programObjectives: [String: Int]
    var createdAt: String
    var organizerName: String
    /// Curve25519 key agreement public key (base64). Agents encrypt their handover to it.
    var organizerPublicKey: String
    /// True on the phone that created the event, which can therefore decrypt handovers.
    var isOrganizer: Bool
    var prospects: [Prospect]
    var receipts: [HandoverReceipt]
    /// Agent side: when the prospects were last shared, and how many there were.
    var lastSentAt: Date?
    var lastSentCount: Int

    var session: Session {
        var s = Session(
            id: id, name: name, date: date, isArchived: isArchived, statutSession: status,
            preRegistered: preRegistered, rdvTargetLow: rdvTargetLow, rdvTargetHigh: rdvTargetHigh,
            programObjectives: Dictionary(uniqueKeysWithValues: programObjectives.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } }),
            createdAt: createdAt
        )
        s.endsAt = endsAt
        return s
    }

    var activeProspects: [Prospect] { prospects.filter { $0.deletedAt == nil } }
}

struct LocalState: Codable, Equatable, Sendable {
    var deviceId = UUID()
    var identity: StoredIdentity?
    var programs: [Program] = []
    var events: [StoredEvent] = []
}
