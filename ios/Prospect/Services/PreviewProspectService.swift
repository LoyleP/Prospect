// Services/PreviewProspectService.swift
// Offline stand-in for SwiftUI previews: sample data, no network.
import Foundation

final class PreviewProspectService: ProspectServiceProtocol, @unchecked Sendable {
    static let programs: [Program] = [
        Program(id: UUID(), name: "Informatique", color: "#3366E6", sortOrder: 0),
        Program(id: UUID(), name: "Design", color: "#9440D9", sortOrder: 1),
        Program(id: UUID(), name: "Commerce", color: "#33B859", sortOrder: 2),
    ]

    private let event = Session(
        id: UUID(), name: "Salon de l'étudiant", date: "2026-11-14", isArchived: false,
        statutSession: .enCours, preRegistered: 40, rdvTargetLow: 20, rdvTargetHigh: 35,
        programObjectives: [:], createdAt: "2026-10-01T09:00:00.000Z"
    )

    private func sampleProspects(for sessionId: UUID) -> [Prospect] {
        let rows: [(String, String, Statut)] = [
            ("Léa", "Durand", .rdvInfo), ("Hugo", "Bernard", .interesse), ("Inès", "Petit", .curieux),
        ]
        return rows.enumerated().map { i, row in
            Prospect(
                id: UUID(), sessionId: sessionId, prenom: row.0, nom: row.1,
                email: "\(row.0.lowercased())@exemple.fr", telephone: "06 12 34 56 7\(i)",
                programId: Self.programs[i % Self.programs.count].id, niveauActuel: NiveauActuel.terminale.rawValue,
                statut: row.2.rawValue, notes: nil, createdBy: nil, agentNom: "Camille Martin",
                createdAt: "2026-11-14T10:0\(i):00.000Z", updatedAt: "2026-11-14T10:0\(i):00.000Z", deletedAt: nil
            )
        }
    }

    func fetchMe() async throws -> MeResponse { throw APIError.network }
    func updateMe(displayName: String?, programIds: [UUID]?) async throws {}
    func createOrganization(name: String, eventLabel: String) async throws -> Organization {
        Organization(id: UUID(), name: name, eventLabel: eventLabel, role: .admin, displayName: "Camille Martin", programIds: [], adminCode: "K7M2QX")
    }
    func joinOrganization(adminCode: String) async throws -> Organization { throw APIError.network }
    func updateOrganization(name: String?, eventLabel: String?) async throws -> Organization { throw APIError.network }
    func regenerateAdminCode() async throws -> Organization { throw APIError.network }

    func fetchPrograms() async throws -> [Program] { Self.programs }
    func createProgram(name: String, color: String?) async throws -> Program {
        Program(id: UUID(), name: name, color: color ?? "#3366E6", sortOrder: 99)
    }
    func updateProgram(id: UUID, name: String?, color: String?, sortOrder: Int?) async throws -> Program { throw APIError.network }
    func deleteProgram(id: UUID) async throws {}

    func fetchAdmins() async throws -> [Admin] {
        [Admin(userId: UUID(), email: "camille@exemple.fr", displayName: "Camille Martin",
               lastSeenAt: "2026-11-14T10:00:00.000Z", createdAt: "2026-10-01T09:00:00.000Z")]
    }
    func removeAdmin(userId: UUID) async throws {}

    func fetchSessionSummaries() async throws -> [SessionSummary] {
        [SessionSummary(session: event, prospectCount: 3, agentCode: "H4TR9P", cfCode: "W2NQ7D")]
    }
    func createSession(name: String, date: Date) async throws -> SessionSummary { throw APIError.network }
    func updateSession(id: UUID, _ patch: SessionPatch) async throws -> SessionSummary { throw APIError.network }
    func deleteSession(id: UUID) async throws {}
    func regenerateCode(sessionId: UUID, role: Role) async throws -> SessionSummary { throw APIError.network }
    func fetchParticipants(sessionId: UUID) async throws -> [Participant] {
        [
            Participant(id: UUID(), displayName: "Hugo", role: .agent, programIds: [],
                        lastSeenAt: "2026-11-14T10:00:00.000Z", createdAt: "2026-11-14T09:00:00.000Z"),
            Participant(id: UUID(), displayName: "Claire", role: .conseillerFormation, programIds: [Self.programs[0].id],
                        lastSeenAt: nil, createdAt: "2026-11-14T09:05:00.000Z"),
        ]
    }
    func removeParticipant(sessionId: UUID, participantId: UUID) async throws {}

    func fetchProspects(sessionId: UUID) async throws -> [Prospect] { sampleProspects(for: sessionId) }
    func createProspect(sessionId: UUID, _ input: ProspectInput) async throws -> Prospect { throw APIError.network }
    func updateProspect(id: UUID, _ input: ProspectInput) async throws -> Prospect { throw APIError.network }
    func archiveProspect(id: UUID) async throws {}
    func restoreProspect(id: UUID) async throws {}
    func fetchArchivedProspects() async throws -> [Prospect] { [] }
    func fetchMyStats() async throws -> MyStats { MyStats(prospects: 12, events: 2, rdv: 5) }
}
