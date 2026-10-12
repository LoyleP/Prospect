// Services/ProspectService.swift
// Every data operation of the app, scoped to the organization currently selected in AppState.
// ViewModels call these methods only — they never build URLs or touch the network.
import Foundation

protocol ProspectServiceProtocol: Sendable {
    // Account
    func fetchMe() async throws -> MeResponse
    func updateMe(displayName: String?, programIds: [UUID]?) async throws
    func createOrganization(name: String, eventLabel: String) async throws -> Organization
    func joinOrganization(adminCode: String) async throws -> Organization
    func updateOrganization(name: String?, eventLabel: String?) async throws -> Organization
    func regenerateAdminCode() async throws -> Organization

    // Programs
    func fetchPrograms() async throws -> [Program]
    func createProgram(name: String, color: String?) async throws -> Program
    func updateProgram(id: UUID, name: String?, color: String?, sortOrder: Int?) async throws -> Program
    func deleteProgram(id: UUID) async throws

    // Admins
    func fetchAdmins() async throws -> [Admin]
    func removeAdmin(userId: UUID) async throws

    // Events
    func fetchSessionSummaries() async throws -> [SessionSummary]
    func createSession(name: String, date: Date) async throws -> SessionSummary
    func updateSession(id: UUID, _ patch: SessionPatch) async throws -> SessionSummary
    func deleteSession(id: UUID) async throws
    func regenerateCode(sessionId: UUID, role: Role) async throws -> SessionSummary
    func fetchParticipants(sessionId: UUID) async throws -> [Participant]
    func removeParticipant(sessionId: UUID, participantId: UUID) async throws

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

final class ProspectService: ProspectServiceProtocol, @unchecked Sendable {
    static let shared = ProspectService()

    /// What view models should use by default: the demo backend when the debug menu enabled it,
    /// the real API otherwise. Read when a view model is created.
    nonisolated(unsafe) static var override: ProspectServiceProtocol?
    static var current: ProspectServiceProtocol { override ?? shared }

    private let api: APIClient
    private let lock = NSLock()
    private var _organizationId: UUID?

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Set by AppState whenever the user switches organization.
    var organizationId: UUID? {
        get { lock.withLock { _organizationId } }
        set { lock.withLock { _organizationId = newValue } }
    }

    private func org(_ suffix: String = "") throws -> String {
        guard let id = organizationId else { throw APIError(status: 404, code: "no_organization", message: "No organization selected") }
        return "/orgs/\(id.uuidString.lowercased())\(suffix)"
    }

    private func path(_ id: UUID) -> String { id.uuidString.lowercased() }

    // MARK: - Account

    func fetchMe() async throws -> MeResponse {
        try await api.get("/me")
    }

    func updateMe(displayName: String?, programIds: [UUID]?) async throws {
        struct Body: Encodable { let display_name: String?; let program_ids: [UUID]? }
        let _: NoContent = try await api.patch("/me", Body(display_name: displayName, program_ids: programIds))
    }

    func createOrganization(name: String, eventLabel: String) async throws -> Organization {
        try await api.post("/orgs", ["name": name, "event_label": eventLabel])
    }

    func joinOrganization(adminCode: String) async throws -> Organization {
        try await api.post("/orgs/join", ["admin_code": adminCode])
    }

    func updateOrganization(name: String?, eventLabel: String?) async throws -> Organization {
        struct Body: Encodable { let name: String?; let event_label: String? }
        return try await api.patch(try org(), Body(name: name, event_label: eventLabel))
    }

    func regenerateAdminCode() async throws -> Organization {
        try await api.post(try org("/admin-code"))
    }

    // MARK: - Programs

    func fetchPrograms() async throws -> [Program] {
        try await api.get(try org("/programs"))
    }

    func createProgram(name: String, color: String?) async throws -> Program {
        struct Body: Encodable { let name: String; let color: String? }
        return try await api.post(try org("/programs"), Body(name: name, color: color))
    }

    func updateProgram(id: UUID, name: String?, color: String?, sortOrder: Int?) async throws -> Program {
        struct Body: Encodable { let name: String?; let color: String?; let sort_order: Int? }
        return try await api.patch(try org("/programs/\(path(id))"), Body(name: name, color: color, sort_order: sortOrder))
    }

    func deleteProgram(id: UUID) async throws {
        try await api.delete(try org("/programs/\(path(id))"))
    }

    // MARK: - Admins

    func fetchAdmins() async throws -> [Admin] {
        try await api.get(try org("/admins"))
    }

    func removeAdmin(userId: UUID) async throws {
        try await api.delete(try org("/admins/\(path(userId))"))
    }

    // MARK: - Events

    func fetchSessionSummaries() async throws -> [SessionSummary] {
        try await api.get(try org("/events"))
    }

    func createSession(name: String, date: Date) async throws -> SessionSummary {
        try await api.post(try org("/events"), ["name": name, "date": Session.isoDay(date)])
    }

    func updateSession(id: UUID, _ patch: SessionPatch) async throws -> SessionSummary {
        try await api.patch(try org("/events/\(path(id))"), patch)
    }

    func deleteSession(id: UUID) async throws {
        try await api.delete(try org("/events/\(path(id))"))
    }

    func regenerateCode(sessionId: UUID, role: Role) async throws -> SessionSummary {
        try await api.post(try org("/events/\(path(sessionId))/codes"), ["role": role.rawValue])
    }

    func fetchParticipants(sessionId: UUID) async throws -> [Participant] {
        try await api.get(try org("/events/\(path(sessionId))/participants"))
    }

    func removeParticipant(sessionId: UUID, participantId: UUID) async throws {
        try await api.delete(try org("/events/\(path(sessionId))/participants/\(path(participantId))"))
    }

    // MARK: - Prospects

    func fetchProspects(sessionId: UUID) async throws -> [Prospect] {
        try await api.get(try org("/events/\(path(sessionId))/prospects"))
    }

    func createProspect(sessionId: UUID, _ input: ProspectInput) async throws -> Prospect {
        try await api.post(try org("/events/\(path(sessionId))/prospects"), input)
    }

    func updateProspect(id: UUID, _ input: ProspectInput) async throws -> Prospect {
        try await api.patch(try org("/prospects/\(path(id))"), input)
    }

    func archiveProspect(id: UUID) async throws {
        let _: Prospect = try await api.post(try org("/prospects/\(path(id))/archive"))
    }

    func restoreProspect(id: UUID) async throws {
        let _: Prospect = try await api.post(try org("/prospects/\(path(id))/restore"))
    }

    func fetchArchivedProspects() async throws -> [Prospect] {
        try await api.get(try org("/prospects/archived"))
    }

    func fetchMyStats() async throws -> MyStats {
        try await api.get(try org("/stats/me"))
    }
}
