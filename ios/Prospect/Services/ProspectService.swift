// Services/ProspectService.swift
// Every data operation of the app, answered from the phone's own store. There is no server: ViewModels
// call these methods and never know where the data lives.
import CryptoKit
import Foundation

protocol ProspectServiceProtocol: Sendable {
    // Programs
    func fetchPrograms() async throws -> [Program]
    func createProgram(name: String, color: String?) async throws -> Program
    func updateProgram(id: UUID, name: String?, color: String?, sortOrder: Int?) async throws -> Program
    func deleteProgram(id: UUID) async throws

    // Events
    func fetchSessionSummaries() async throws -> [SessionSummary]
    func createSession(name: String, date: Date) async throws -> SessionSummary
    func updateSession(id: UUID, _ patch: SessionPatch) async throws -> SessionSummary
    func deleteSession(id: UUID) async throws

    // Prospects
    func fetchProspects(sessionId: UUID) async throws -> [Prospect]
    func createProspect(sessionId: UUID, _ input: ProspectInput) async throws -> Prospect
    func updateProspect(id: UUID, _ input: ProspectInput) async throws -> Prospect
    func archiveProspect(id: UUID) async throws
    func restoreProspect(id: UUID) async throws
    func fetchArchivedProspects() async throws -> [Prospect]
    func fetchMyStats() async throws -> MyStats
}

struct MyStats: Decodable, Sendable, Equatable {
    let prospects: Int
    let events: Int
    let rdv: Int
}

enum ServiceError: LocalizedError, Equatable {
    case notFound, notAllowed, noIdentity

    var errorDescription: String? {
        switch self {
        case .notFound:   return L("Item not found.")
        case .notAllowed: return L("Only the organizer can do that.")
        case .noIdentity: return L("Choose your name first.")
        }
    }
}

final class ProspectService: ProspectServiceProtocol, @unchecked Sendable {
    static let shared = ProspectService(store: .shared, keys: KeychainKeyVault())

    /// What view models use by default: the debug demo store when one is active, the real store otherwise.
    nonisolated(unsafe) static var override: ProspectServiceProtocol?
    static var current: ProspectServiceProtocol { override ?? shared }

    let store: LocalStore
    let keys: KeyVault

    init(store: LocalStore, keys: KeyVault) {
        self.store = store
        self.keys = keys
    }

    // MARK: Time

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static func iso(_ date: Date = Date()) -> String { isoFormatter.string(from: date) }

    // MARK: Programs

    func fetchPrograms() async throws -> [Program] {
        store.read { $0.programs.sorted { $0.sortOrder < $1.sortOrder } }
    }

    func createProgram(name: String, color: String?) async throws -> Program {
        store.write { state in
            let program = Program(id: UUID(), name: name, color: color ?? Program.palette[state.programs.count % Program.palette.count],
                                  sortOrder: (state.programs.map(\.sortOrder).max() ?? -1) + 1)
            state.programs.append(program)
            return program
        }
    }

    func updateProgram(id: UUID, name: String?, color: String?, sortOrder: Int?) async throws -> Program {
        try store.write { state in
            guard let i = state.programs.firstIndex(where: { $0.id == id }) else { throw ServiceError.notFound }
            if let name { state.programs[i].name = name }
            if let color { state.programs[i].color = color }
            if let sortOrder { state.programs[i].sortOrder = sortOrder }
            return state.programs[i]
        }
    }

    func deleteProgram(id: UUID) async throws {
        store.write { state in
            state.programs.removeAll { $0.id == id }
            for e in state.events.indices {
                state.events[e].programObjectives[id.uuidString] = nil
                for p in state.events[e].prospects.indices where state.events[e].prospects[p].programId == id {
                    state.events[e].prospects[p].programId = nil
                }
            }
        }
    }

    // MARK: Events

    private func summary(_ e: StoredEvent) -> SessionSummary {
        SessionSummary(session: e.session, prospectCount: e.activeProspects.count)
    }

    func fetchSessionSummaries() async throws -> [SessionSummary] {
        store.read { $0.events.sorted { $0.date > $1.date }.map(summary) }
    }

    func createSession(name: String, date: Date) async throws -> SessionSummary {
        guard let identity = store.read({ $0.identity }) else { throw ServiceError.noIdentity }
        guard identity.role == .admin else { throw ServiceError.notAllowed }
        let id = UUID()
        let key = Curve25519.KeyAgreement.PrivateKey()
        keys.store(key, for: id)
        let event = StoredEvent(
            id: id, name: name, date: Session.isoDay(date), endsAt: nil, status: .enCours, isArchived: false,
            preRegistered: 0, rdvTargetLow: 0, rdvTargetHigh: 0, programObjectives: [:], createdAt: Self.iso(),
            organizerName: identity.displayName, organizerPublicKey: key.publicKey.rawRepresentation.base64EncodedString(),
            isOrganizer: true, prospects: [], receipts: [], lastSentAt: nil, lastSentCount: 0, importsComplete: false
        )
        store.write { $0.events.append(event) }
        return summary(event)
    }

    func updateSession(id: UUID, _ patch: SessionPatch) async throws -> SessionSummary {
        try store.write { state in
            guard let i = state.events.firstIndex(where: { $0.id == id }) else { throw ServiceError.notFound }
            // An agent only keeps their own local copy; the event itself belongs to the organizer.
            let owns = state.events[i].isOrganizer
            if owns {
                if let v = patch.name { state.events[i].name = v }
                if let v = patch.date { state.events[i].date = v }
                if let v = patch.status { state.events[i].status = v }
                if let v = patch.preRegistered { state.events[i].preRegistered = v }
                if let v = patch.rdvTargetLow { state.events[i].rdvTargetLow = v }
                if let v = patch.rdvTargetHigh { state.events[i].rdvTargetHigh = v }
                if let v = patch.programObjectives { state.events[i].programObjectives = v }
                if let v = patch.endsAt { state.events[i].endsAt = v }
            }
            if let v = patch.isArchived { state.events[i].isArchived = v }
            return summary(state.events[i])
        }
    }

    func deleteSession(id: UUID) async throws {
        store.write { $0.events.removeAll { $0.id == id } }
        keys.remove(for: id)
    }

    // MARK: Prospects

    func fetchProspects(sessionId: UUID) async throws -> [Prospect] {
        store.read { state in
            (state.events.first { $0.id == sessionId }?.activeProspects ?? []).sorted { $0.createdAt > $1.createdAt }
        }
    }

    func createProspect(sessionId: UUID, _ input: ProspectInput) async throws -> Prospect {
        try store.write { state in
            guard let identity = state.identity else { throw ServiceError.noIdentity }
            guard let e = state.events.firstIndex(where: { $0.id == sessionId }) else { throw ServiceError.notFound }
            let id = input.clientId ?? UUID()
            if let existing = state.events[e].prospects.first(where: { $0.id == id }) { return existing }
            let now = Self.iso()
            let p = Prospect(
                id: id, sessionId: sessionId, prenom: input.prenom, nom: input.nom, email: input.email,
                telephone: input.telephone, programId: input.programId, niveauActuel: input.niveauActuel,
                statut: input.statut, notes: input.notes, createdBy: state.deviceId, agentNom: identity.displayName,
                createdAt: now, updatedAt: now, deletedAt: nil
            )
            state.events[e].prospects.append(p)
            return p
        }
    }

    func updateProspect(id: UUID, _ input: ProspectInput) async throws -> Prospect {
        try store.write { state in
            guard let (e, p) = Self.locate(id, in: state) else { throw ServiceError.notFound }
            var prospect = state.events[e].prospects[p]
            prospect.prenom = input.prenom; prospect.nom = input.nom; prospect.email = input.email
            prospect.telephone = input.telephone; prospect.programId = input.programId
            prospect.niveauActuel = input.niveauActuel; prospect.statut = input.statut; prospect.notes = input.notes
            prospect.updatedAt = Self.iso()
            state.events[e].prospects[p] = prospect
            return prospect
        }
    }

    func archiveProspect(id: UUID) async throws {
        try setDeleted(id, to: Self.iso())
    }

    func restoreProspect(id: UUID) async throws {
        try setDeleted(id, to: nil)
    }

    private func setDeleted(_ id: UUID, to value: String?) throws {
        try store.write { state in
            guard let (e, p) = Self.locate(id, in: state) else { throw ServiceError.notFound }
            state.events[e].prospects[p].deletedAt = value
            state.events[e].prospects[p].updatedAt = Self.iso()
        }
    }

    func fetchArchivedProspects() async throws -> [Prospect] {
        store.read { state in
            state.events.flatMap { $0.prospects.filter { $0.deletedAt != nil } }.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func fetchMyStats() async throws -> MyStats {
        store.read { state in
            let mine = state.events.flatMap { $0.activeProspects }.filter { $0.createdBy == state.deviceId }
            let rdv = mine.filter { $0.statut == Statut.rdvInfo.rawValue || $0.statut == Statut.rdvAdmission.rawValue }.count
            return MyStats(prospects: mine.count, events: Set(mine.map(\.sessionId)).count, rdv: rdv)
        }
    }

    private static func locate(_ id: UUID, in state: LocalState) -> (Int, Int)? {
        for (e, event) in state.events.enumerated() {
            if let p = event.prospects.firstIndex(where: { $0.id == id }) { return (e, p) }
        }
        return nil
    }
}
