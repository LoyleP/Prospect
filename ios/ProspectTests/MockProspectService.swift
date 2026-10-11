// ProspectTests/MockProspectService.swift
// In-memory ProspectServiceProtocol that records what view models ask for.
import Foundation
@testable import Prospect

final class MockProspectService: ProspectServiceProtocol, @unchecked Sendable {
    var programs: [Program] = []
    var participants: [Participant] = []
    var summaries: [SessionSummary] = []
    var prospects: [Prospect] = []
    var errorToThrow: Error?

    private(set) var createdInputs: [(sessionId: UUID, input: ProspectInput)] = []
    private(set) var updatedInputs: [(id: UUID, input: ProspectInput)] = []
    private(set) var sessionPatches: [(id: UUID, patch: SessionPatch)] = []
    private(set) var archivedIds: [UUID] = []

    private func check() throws { if let errorToThrow { throw errorToThrow } }

    func fetchMe() async throws -> MeResponse { throw APIError.network }
    func updateMe(displayName: String?, programIds: [UUID]?) async throws { try check() }
    func createOrganization(name: String, eventLabel: String) async throws -> Organization {
        try check()
        return Organization(id: UUID(), name: name, eventLabel: eventLabel, role: .admin, displayName: "Test", programIds: [])
    }
    func joinOrganization(adminCode: String) async throws -> Organization { throw APIError.network }
    func updateOrganization(name: String?, eventLabel: String?) async throws -> Organization { throw APIError.network }
    func regenerateAdminCode() async throws -> Organization { throw APIError.network }

    func fetchPrograms() async throws -> [Program] { try check(); return programs }
    func createProgram(name: String, color: String?) async throws -> Program { throw APIError.network }
    func updateProgram(id: UUID, name: String?, color: String?, sortOrder: Int?) async throws -> Program { throw APIError.network }
    func deleteProgram(id: UUID) async throws {}

    func fetchAdmins() async throws -> [Admin] { [] }
    func removeAdmin(userId: UUID) async throws {}

    func fetchSessionSummaries() async throws -> [SessionSummary] { try check(); return summaries }
    func createSession(name: String, date: Date) async throws -> SessionSummary { throw APIError.network }
    func updateSession(id: UUID, _ patch: SessionPatch) async throws -> SessionSummary {
        try check()
        sessionPatches.append((id, patch))
        guard let s = summaries.first(where: { $0.id == id }) else { throw APIError(status: 404, code: "not_found", message: "") }
        return s
    }
    func deleteSession(id: UUID) async throws {}
    func regenerateCode(sessionId: UUID, role: Role) async throws -> SessionSummary { throw APIError.network }
    func fetchParticipants(sessionId: UUID) async throws -> [Participant] { try check(); return participants }
    func removeParticipant(sessionId: UUID, participantId: UUID) async throws {}

    func fetchProspects(sessionId: UUID) async throws -> [Prospect] {
        try check()
        return prospects.filter { $0.sessionId == sessionId }
    }
    func createProspect(sessionId: UUID, _ input: ProspectInput) async throws -> Prospect {
        try check()
        createdInputs.append((sessionId, input))
        return TestData.prospect(sessionId: sessionId, prenom: input.prenom, nom: input.nom, programId: input.programId)
    }
    func updateProspect(id: UUID, _ input: ProspectInput) async throws -> Prospect {
        try check()
        updatedInputs.append((id, input))
        return TestData.prospect(id: id, prenom: input.prenom, nom: input.nom, programId: input.programId)
    }
    func archiveProspect(id: UUID) async throws { try check(); archivedIds.append(id) }
    func restoreProspect(id: UUID) async throws {}
    func fetchArchivedProspects() async throws -> [Prospect] { [] }
    func fetchMyStats() async throws -> MyStats { MyStats(prospects: 0, events: 0, rdv: 0) }
}

enum TestData {
    static func session(id: UUID = UUID(), status: SessionStatut = .enCours, preRegistered: Int = 0) -> Session {
        Session(
            id: id, name: "Salon test", date: "2026-11-14", isArchived: false, statutSession: status,
            preRegistered: preRegistered, rdvTargetLow: 0, rdvTargetHigh: 0, programObjectives: [:],
            createdAt: "2026-10-01T09:00:00.000Z"
        )
    }

    static func prospect(
        id: UUID = UUID(), sessionId: UUID = UUID(), prenom: String = "Léa", nom: String = "Durand",
        programId: UUID? = nil, statut: Statut = .curieux, agent: String = "Camille"
    ) -> Prospect {
        Prospect(
            id: id, sessionId: sessionId, prenom: prenom, nom: nom, email: "lea@exemple.fr",
            telephone: "0612345678", programId: programId, niveauActuel: NiveauActuel.terminale.rawValue,
            statut: statut.rawValue, notes: nil, createdBy: nil, agentNom: agent,
            createdAt: "2026-11-14T10:00:00.000Z", updatedAt: "2026-11-14T10:00:00.000Z", deletedAt: nil
        )
    }
}
