// Local/DemoSeed.swift
// Realistic data for the debug menu, SwiftUI previews and screenshots. It lives in memory (or a throwaway
// store) and is never touched by a normal run of the app.
import CryptoKit
import Foundation

enum DemoSeed {
    enum Kind: String, CaseIterable {
        case fresh, organizerEmpty, organizerFull, agentFull
    }

    struct Seeded {
        let store: LocalStore
        let keys: MemoryKeyVault
        let service: ProspectService
    }

    static let liveEventId = UUID(uuidString: "00000000-0000-4000-8000-0000000000E1")!

    static func make(_ kind: Kind, now: Date = Date()) -> Seeded {
        let keys = MemoryKeyVault()
        var state = LocalState()
        switch kind {
        case .fresh:
            break
        case .organizerEmpty:
            state.identity = StoredIdentity(displayName: "Camille Martin", role: .admin, eventLabel: "Salon")
        case .organizerFull:
            state.identity = StoredIdentity(displayName: "Camille Martin", role: .admin, eventLabel: "Salon")
            state.programs = programs()
            state.events = organizerEvents(state: state, keys: keys, now: now)
        case .agentFull:
            state.identity = StoredIdentity(displayName: "Hugo Petit", role: .agent, eventLabel: "Salon")
            state.programs = programs()
            state.events = [agentEvent(state: state, now: now)]
        }
        let store = LocalStore(url: nil, initial: state)
        return Seeded(store: store, keys: keys, service: ProspectService(store: store, keys: keys))
    }

    // MARK: Data

    static func programs() -> [Program] {
        [("Informatique", "#2EC7BF"), ("Design & Création", "#3366E6"), ("Commerce", "#F2D11A"), ("Audiovisuel", "#E85D9F"), ("Architecture", "#22D3EE")]
            .enumerated().map { Program(id: UUID(), name: $1.0, color: $1.1, sortOrder: $0) }
    }

    private static func day(_ offset: Int, from now: Date) -> String {
        Session.isoDay(Calendar.current.date(byAdding: .day, value: offset, to: now) ?? now)
    }

    private static let people: [(String, String, Statut, Int, Int, String)] = [
        ("Léa", "Durand", .rdvAdmission, 0, 4, "Camille Martin"), ("Hugo", "Bernard", .interesse, 1, 5, "Hugo Petit"),
        ("Inès", "Moreau", .rdvInfo, 3, 7, "Camille Martin"), ("Noé", "Lambert", .curieux, 1, 8, "Sofia Rossi"),
        ("Jade", "Fournier", .rdvInfo, 0, 10, "Hugo Petit"), ("Lucas", "Girard", .interesse, 2, 11, "Sofia Rossi"),
        ("Emma", "Roux", .curieux, 4, 14, "Camille Martin"), ("Tom", "Blanc", .rdvAdmission, 1, 16, "Hugo Petit"),
        ("Manon", "Garnier", .rdvInfo, 0, 19, "Sofia Rossi"), ("Louis", "Faure", .curieux, 2, 22, "Camille Martin"),
        ("Chloé", "Mercier", .interesse, 3, 25, "Hugo Petit"), ("Gabin", "Lopez", .rdvInfo, 1, 28, "Sofia Rossi"),
        ("Zoé", "Henry", .curieux, 0, 31, "Camille Martin"), ("Adam", "Perrin", .interesse, 1, 35, "Hugo Petit"),
        ("Lina", "Colin", .rdvAdmission, 2, 38, "Sofia Rossi"), ("Nathan", "Vidal", .curieux, 4, 44, "Camille Martin"),
        ("Eva", "Caron", .rdvInfo, 3, 47, "Hugo Petit"), ("Théo", "Marchand", .interesse, 0, 52, "Sofia Rossi"),
    ]

    private static func prospects(event: UUID, programs: [Program], authors: [String: UUID], only: String? = nil, now: Date) -> [Prospect] {
        let levels = ["Terminale", "Bac +1", "Terminale", "Bac +2", "< Terminale", "Terminale"]
        return people.enumerated().compactMap { i, p in
            if let only, p.5 != only { return nil }
            let created = now.addingTimeInterval(-Double(p.4 > 20 ? p.4 * 7 : p.4) * 60)
            let stamp = ProspectService.iso(created)
            return Prospect(
                id: UUID(), sessionId: event, prenom: p.0, nom: p.1, email: "\(p.0.lowercased())@exemple.fr",
                telephone: "06 12 34 56 \(String(format: "%02d", 10 + i))", programId: programs[p.3].id,
                niveauActuel: levels[i % levels.count], statut: p.2.rawValue,
                notes: i % 4 == 0 ? "Intéressé(e) par une alternance." : nil,
                createdBy: authors[p.5], agentNom: p.5, createdAt: stamp, updatedAt: stamp, deletedAt: nil
            )
        }
    }

    private static func organizerEvents(state: LocalState, keys: MemoryKeyVault, now: Date) -> [StoredEvent] {
        func event(_ id: UUID, _ name: String, _ dayOffset: Int, _ status: SessionStatut, _ list: [Prospect], _ receipts: [HandoverReceipt]) -> StoredEvent {
            let key = Curve25519.KeyAgreement.PrivateKey()
            keys.store(key, for: id)
            return StoredEvent(
                id: id, name: name, date: day(dayOffset, from: now), endsAt: nil, status: status, isArchived: false,
                preRegistered: status == .enCours ? 60 : 0, rdvTargetLow: status == .enCours ? 45 : 0, rdvTargetHigh: status == .enCours ? 65 : 0,
                programObjectives: [:], createdAt: ProspectService.iso(now.addingTimeInterval(-86_400 * 3)),
                organizerName: state.identity?.displayName ?? "", organizerPublicKey: key.publicKey.rawRepresentation.base64EncodedString(),
                isOrganizer: true, prospects: list, receipts: receipts, lastSentAt: nil, lastSentCount: 0, importsComplete: false
            )
        }
        let authors = ["Camille Martin": state.deviceId, "Hugo Petit": UUID(), "Sofia Rossi": UUID()]
        let live = prospects(event: liveEventId, programs: state.programs, authors: authors, now: now)
        let receipts = [
            HandoverReceipt(id: authors["Hugo Petit"]!, agentName: "Hugo Petit", count: 6, added: 6, receivedAt: now.addingTimeInterval(-1_800)),
        ]
        return [
            event(liveEventId, "Salon de l'étudiant", 0, .enCours, live, receipts),
            event(UUID(), "Forum d'orientation", 21, .pasCommence, [], []),
            event(UUID(), "Portes ouvertes de mars", -42, .termine, [], []),
        ]
    }

    private static func agentEvent(state: LocalState, now: Date) -> StoredEvent {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let list = prospects(event: liveEventId, programs: state.programs, authors: ["Hugo Petit": state.deviceId], only: "Hugo Petit", now: now)
        return StoredEvent(
            id: liveEventId, name: "Salon de l'étudiant", date: day(0, from: now), endsAt: now.addingTimeInterval(4 * 3600),
            status: .enCours, isArchived: false, preRegistered: 0, rdvTargetLow: 0, rdvTargetHigh: 0, programObjectives: [:],
            createdAt: ProspectService.iso(now.addingTimeInterval(-3_600)), organizerName: "Camille Martin",
            organizerPublicKey: key.publicKey.rawRepresentation.base64EncodedString(), isOrganizer: false,
            prospects: list, receipts: [], lastSentAt: nil, lastSentCount: 0, importsComplete: true
        )
    }
}

extension DemoSeed {
    /// A file as an agent named Sofia Rossi would send it: 3 new prospects and 2 the organizer already has
    /// (same email), sealed to the event's public key.
    static func simulatedHandover(for event: StoredEvent, now: Date = Date()) throws -> Data {
        let agentId = UUID(uuidString: "00000000-0000-4000-8000-0000000000B2")!
        let stamp = ProspectService.iso(now)
        func make(_ first: String, _ last: String, email: String, phone: String, statut: Statut) -> Prospect {
            Prospect(id: UUID(), sessionId: event.id, prenom: first, nom: last, email: email, telephone: phone, programId: nil,
                     niveauActuel: "Terminale", statut: statut.rawValue, notes: nil, createdBy: agentId,
                     agentNom: "Sofia Rossi", createdAt: stamp, updatedAt: stamp, deletedAt: nil)
        }
        let known = event.activeProspects.prefix(2)
        let duplicates = known.map { make($0.prenom, $0.nom, email: $0.email, phone: "06 99 00 00 0\(Int.random(in: 0...9))", statut: .interesse) }
        let fresh = [
            make("Maya", "Bertrand", email: "maya.bertrand@exemple.fr", phone: "06 55 10 20 31", statut: .curieux),
            make("Rayan", "Meyer", email: "rayan.meyer@exemple.fr", phone: "06 55 10 20 32", statut: .rdvInfo),
            make("Alice", "Noël", email: "alice.noel@exemple.fr", phone: "06 55 10 20 33", statut: .interesse),
        ]
        let payload = Handover.Payload(agentId: agentId, agentName: "Sofia Rossi", sentAt: now, prospects: Array(duplicates) + fresh)
        return try Handover.seal(payload, eventId: event.id, organizerPublicKey: event.organizerPublicKey)
    }
}

extension AppState {
    /// SwiftUI previews: an app state backed by seeded in-memory data.
    static func preview(_ kind: DemoSeed.Kind = .organizerFull) -> AppState {
        let seeded = DemoSeed.make(kind)
        ProspectService.override = seeded.service
        return AppState(store: seeded.store, exchange: EventExchange(store: seeded.store, keys: seeded.keys))
    }
}
