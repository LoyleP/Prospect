// Services/DemoProspectService.swift
// A stateful, offline stand-in for the API: realistic seeded data that you can actually
// edit (create / edit / archive prospects, change events, regenerate codes…).
// Used by the debug menu, SwiftUI previews and screenshots — never by a release build's
// normal flow, because `DemoMode.active` is only set from the debug menu.
import Foundation

/// The currently active demo backend, if any. When set, `AuthService` and `ProspectService.current`
/// answer from it instead of the network.
enum DemoMode {
    nonisolated(unsafe) static var active: DemoProspectService?
}

final class DemoProspectService: ProspectServiceProtocol, @unchecked Sendable {

    enum Identity: Equatable {
        case admin(name: String)
        case participant(role: Role, name: String)
    }

    struct Setup {
        var identity: Identity = .admin(name: "Camille Martin")
        var hasOrganization = true
        /// Programs, events, prospects and participants. `false` = a brand new, empty organization.
        var populated = true
        var eventLabel = "Salon"
        var signedIn = true
    }

    // MARK: State

    private let lock = NSLock()
    private var identity: Identity
    private var signedIn: Bool
    private var organization: Organization?
    private var programs: [Program] = []
    private var events: [SessionSummary] = []
    private var prospects: [Prospect] = []
    private var participants: [Participant] = []
    private var eventLabel: String

    static let orgId = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!

    init(_ setup: Setup = Setup()) {
        identity = setup.identity
        signedIn = setup.signedIn
        eventLabel = setup.eventLabel
        if setup.hasOrganization {
            let role: Role
            let name: String
            switch setup.identity {
            case .admin(let n):                 role = .admin; name = n
            case .participant(let r, let n):    role = r; name = n
            }
            organization = Organization(
                id: Self.orgId, name: "Atelier Horizon", eventLabel: setup.eventLabel, role: role,
                displayName: name, programIds: [], adminCode: role == .admin ? "K7M2QX" : nil
            )
            if setup.populated { seed() }
        }
    }

    var isSignedIn: Bool { lock.withLock { signedIn } }

    // MARK: Sign-in simulation (used by AuthService in demo mode)

    enum DemoSignIn {
        case admin(name: String, hasOrganization: Bool)
        case participant(code: String, name: String)
    }

    func simulateSignIn(_ kind: DemoSignIn) async throws {
        try await Task.sleep(for: .milliseconds(650))
        lock.lock(); defer { lock.unlock() }
        switch kind {
        case .admin(let name, let hasOrg):
            identity = .admin(name: name)
            if hasOrg {
                if organization == nil { organization = Organization(id: Self.orgId, name: "Atelier Horizon", eventLabel: eventLabel, role: .admin, displayName: name, programIds: [], adminCode: "K7M2QX"); seedLocked() }
            } else {
                organization = nil; programs = []; events = []; prospects = []; participants = []
            }
        case .participant(let code, let name):
            if code.uppercased() == "XXXXXX" {
                throw APIError(status: 401, code: "invalid_code", message: "This code is invalid or the event is closed")
            }
            let role: Role = code.uppercased().hasPrefix("C") ? .conseillerFormation : .agent
            identity = .participant(role: role, name: name)
            if organization == nil { organization = Organization(id: Self.orgId, name: "Atelier Horizon", eventLabel: eventLabel, role: role, displayName: name, programIds: [], adminCode: nil); seedLocked() }
            organization?.role = role
            organization?.displayName = name
            organization?.adminCode = nil
        }
        signedIn = true
    }

    func signOut() { lock.withLock { signedIn = false } }

    // MARK: Seed

    private func seed() { lock.withLock { seedLocked() } }

    private func seedLocked() {
        programs = [
            Program(id: UUID(), name: "Design & Création", color: "#5B7CFF", sortOrder: 0),
            Program(id: UUID(), name: "Informatique", color: "#34D399", sortOrder: 1),
            Program(id: UUID(), name: "Commerce", color: "#FBBF24", sortOrder: 2),
            Program(id: UUID(), name: "Audiovisuel", color: "#F472B6", sortOrder: 3),
            Program(id: UUID(), name: "Architecture", color: "#22D3EE", sortOrder: 4),
        ]
        let today = Calendar.current.startOfDay(for: Date())
        func day(_ offset: Int) -> String { Session.isoDay(Calendar.current.date(byAdding: .day, value: offset, to: today)!) }

        let live = Session(
            id: UUID(), name: "Salon de l'étudiant", date: day(0), isArchived: false, statutSession: .enCours,
            preRegistered: 60, rdvTargetLow: 45, rdvTargetHigh: 65,
            programObjectives: [:], createdAt: Self.iso(Date().addingTimeInterval(-86_400 * 12))
        )
        let past = Session(
            id: UUID(), name: "Portes ouvertes de mars", date: day(-42), isArchived: false, statutSession: .termine,
            preRegistered: 80, rdvTargetLow: 50, rdvTargetHigh: 60,
            programObjectives: [:], createdAt: Self.iso(Date().addingTimeInterval(-86_400 * 60))
        )
        let upcoming = Session(
            id: UUID(), name: "Forum d'orientation", date: day(21), isArchived: false, statutSession: .pasCommence,
            preRegistered: 0, rdvTargetLow: 0, rdvTargetHigh: 0,
            programObjectives: [:], createdAt: Self.iso(Date().addingTimeInterval(-86_400 * 2))
        )
        events = [
            SessionSummary(session: live, prospectCount: 0, agentCode: "H4TR9P", cfCode: "C2NQ7D"),
            SessionSummary(session: upcoming, prospectCount: 0, agentCode: "M8KX3W", cfCode: "CV5Y2B"),
            SessionSummary(session: past, prospectCount: 0, agentCode: "P6DA4R", cfCode: "CT9E7F"),
        ]

        let people: [(String, String, Statut, Int, Int, String)] = [
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
        let levels = ["Terminale", "Bac +1", "Terminale", "Bac +2", "< Terminale", "Terminale"]
        prospects = people.enumerated().map { i, p in
            let created = Date().addingTimeInterval(-Double(p.4 > 20 ? p.4 * 7 : p.4) * 60)
            return Prospect(
                id: UUID(), sessionId: live.id, prenom: p.0, nom: p.1,
                email: "\(p.0.lowercased())@exemple.fr", telephone: "06 12 34 56 \(String(format: "%02d", 10 + i))",
                programId: programs[p.3].id, niveauActuel: levels[i % levels.count], statut: p.2.rawValue,
                notes: i % 4 == 0 ? "Intéressé(e) par une alternance." : nil, createdBy: nil, agentNom: p.5,
                createdAt: Self.iso(created), updatedAt: Self.iso(created), deletedAt: nil
            )
        }
        participants = [
            Participant(id: UUID(), displayName: "Hugo Petit", role: .agent, programIds: [], lastSeenAt: Self.iso(Date()), createdAt: Self.iso(Date().addingTimeInterval(-7200))),
            Participant(id: UUID(), displayName: "Sofia Rossi", role: .agent, programIds: [], lastSeenAt: Self.iso(Date().addingTimeInterval(-600)), createdAt: Self.iso(Date().addingTimeInterval(-6800))),
            Participant(id: UUID(), displayName: "Julien Morel", role: .conseillerFormation, programIds: [programs[0].id, programs[4].id], lastSeenAt: nil, createdAt: Self.iso(Date().addingTimeInterval(-5400))),
            Participant(id: UUID(), displayName: "Amélie Lucas", role: .conseillerFormation, programIds: [programs[1].id], lastSeenAt: nil, createdAt: Self.iso(Date().addingTimeInterval(-5000))),
        ]
        refreshCounts()
    }

    private func refreshCounts() {
        events = events.map { e in
            var copy = e
            copy = SessionSummary(
                session: e.session,
                prospectCount: prospects.filter { $0.sessionId == e.id && $0.deletedAt == nil }.count,
                agentCode: e.agentCode, cfCode: e.cfCode
            )
            return copy
        }
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private static func randomCode(prefix: String = "") -> String {
        let alphabet = Array("ABDEFGHJKMNPQRSTUVWXYZ23456789")
        return prefix + String((0..<(6 - prefix.count)).map { _ in alphabet.randomElement()! })
    }

    private var isAdmin: Bool { if case .admin = identity { return true } else { return false } }
    private var displayName: String {
        switch identity { case .admin(let n): return n; case .participant(_, let n): return n }
    }

    // MARK: Account

    func fetchMe() async throws -> MeResponse {
        lock.lock(); defer { lock.unlock() }
        switch identity {
        case .admin(let name):
            return .admin(
                user: .init(id: UUID(uuidString: "00000000-0000-4000-8000-0000000000B1")!, email: "camille@atelier-horizon.fr", displayName: name),
                organizations: organization.map { [$0] } ?? []
            )
        case .participant(let role, let name):
            guard let org = organization, let live = events.first(where: { $0.statutSession == .enCours }) ?? events.first else { throw APIError.network }
            let hidden = SessionSummary(session: live.session, prospectCount: live.prospectCount)
            return .participant(participant: .init(id: UUID(), displayName: name, role: role), organization: org, event: hidden)
        }
    }

    func updateMe(displayName: String?, programIds: [UUID]?) async throws {
        lock.withLock {
            if let displayName, case .admin = identity { identity = .admin(name: displayName) }
            if let displayName { organization?.displayName = displayName }
            if let programIds { organization?.programIds = programIds }
        }
    }

    func createOrganization(name: String, eventLabel: String) async throws -> Organization {
        try await Task.sleep(for: .milliseconds(450))
        return lock.withLock {
            self.eventLabel = eventLabel
            let org = Organization(id: Self.orgId, name: name, eventLabel: eventLabel, role: .admin, displayName: displayName, programIds: [], adminCode: Self.randomCode())
            organization = org
            return org
        }
    }

    func joinOrganization(adminCode: String) async throws -> Organization {
        try await Task.sleep(for: .milliseconds(450))
        if adminCode.uppercased() == "XXXXXX" { throw APIError(status: 401, code: "invalid_code", message: "invalid") }
        return lock.withLock {
            if organization == nil {
                organization = Organization(id: Self.orgId, name: "Atelier Horizon", eventLabel: eventLabel, role: .admin, displayName: displayName, programIds: [], adminCode: adminCode.uppercased())
                seedLocked()
            }
            return organization!
        }
    }

    func updateOrganization(name: String?, eventLabel: String?) async throws -> Organization {
        lock.withLock {
            if let name { organization?.name = name }
            if let eventLabel { organization?.eventLabel = eventLabel; self.eventLabel = eventLabel }
            return organization!
        }
    }

    func regenerateAdminCode() async throws -> Organization {
        lock.withLock { organization?.adminCode = Self.randomCode(); return organization! }
    }

    // MARK: Programs

    func fetchPrograms() async throws -> [Program] { lock.withLock { programs.sorted { $0.sortOrder < $1.sortOrder } } }

    func createProgram(name: String, color: String?) async throws -> Program {
        lock.withLock {
            let p = Program(id: UUID(), name: name, color: color ?? Program.palette[programs.count % Program.palette.count], sortOrder: programs.count)
            programs.append(p)
            return p
        }
    }

    func updateProgram(id: UUID, name: String?, color: String?, sortOrder: Int?) async throws -> Program {
        try lock.withLock {
            guard let i = programs.firstIndex(where: { $0.id == id }) else { throw APIError(status: 404, code: "not_found", message: "") }
            if let name { programs[i].name = name }
            if let color { programs[i].color = color }
            if let sortOrder { programs[i].sortOrder = sortOrder }
            return programs[i]
        }
    }

    func deleteProgram(id: UUID) async throws {
        lock.withLock {
            programs.removeAll { $0.id == id }
            for i in prospects.indices where prospects[i].programId == id { prospects[i].programId = nil }
        }
    }

    // MARK: Admins

    func fetchAdmins() async throws -> [Admin] {
        lock.withLock {
            [
                Admin(userId: UUID(uuidString: "00000000-0000-4000-8000-0000000000B1")!, email: "camille@atelier-horizon.fr", displayName: displayName, lastSeenAt: Self.iso(Date()), createdAt: Self.iso(Date().addingTimeInterval(-86_400 * 30))),
                Admin(userId: UUID(), email: "paul@atelier-horizon.fr", displayName: "Paul Verdier", lastSeenAt: Self.iso(Date().addingTimeInterval(-86_400)), createdAt: Self.iso(Date().addingTimeInterval(-86_400 * 20))),
            ]
        }
    }

    func removeAdmin(userId: UUID) async throws {}

    // MARK: Events

    func fetchSessionSummaries() async throws -> [SessionSummary] {
        lock.withLock {
            refreshCounts()
            return isAdmin ? events : events.filter { $0.statutSession == .enCours }.map { SessionSummary(session: $0.session, prospectCount: $0.prospectCount) }
        }
    }

    func createSession(name: String, date: Date) async throws -> SessionSummary {
        lock.withLock {
            let session = Session(id: UUID(), name: name, date: Session.isoDay(date), isArchived: false, statutSession: .pasCommence, preRegistered: 0, rdvTargetLow: 0, rdvTargetHigh: 0, programObjectives: [:], createdAt: Self.iso(Date()))
            let summary = SessionSummary(session: session, prospectCount: 0, agentCode: Self.randomCode(), cfCode: Self.randomCode(prefix: "C"))
            events.insert(summary, at: 0)
            return summary
        }
    }

    func updateSession(id: UUID, _ patch: SessionPatch) async throws -> SessionSummary {
        try lock.withLock {
            guard let i = events.firstIndex(where: { $0.id == id }) else { throw APIError(status: 404, code: "not_found", message: "") }
            var s = events[i].session
            if let v = patch.name { s = Session(id: s.id, name: v, date: s.date, isArchived: s.isArchived, statutSession: s.statutSession, preRegistered: s.preRegistered, rdvTargetLow: s.rdvTargetLow, rdvTargetHigh: s.rdvTargetHigh, programObjectives: s.programObjectives, createdAt: s.createdAt) }
            if let v = patch.date { s = Session(id: s.id, name: s.name, date: v, isArchived: s.isArchived, statutSession: s.statutSession, preRegistered: s.preRegistered, rdvTargetLow: s.rdvTargetLow, rdvTargetHigh: s.rdvTargetHigh, programObjectives: s.programObjectives, createdAt: s.createdAt) }
            if let v = patch.status { s.statutSession = v }
            if let v = patch.isArchived { s.isArchived = v }
            if let v = patch.preRegistered { s.preRegistered = v }
            if let v = patch.rdvTargetLow { s.rdvTargetLow = v }
            if let v = patch.rdvTargetHigh { s.rdvTargetHigh = v }
            if let v = patch.programObjectives {
                s.programObjectives = Dictionary(uniqueKeysWithValues: v.compactMap { k, n in UUID(uuidString: k).map { ($0, n) } })
            }
            events[i] = SessionSummary(session: s, prospectCount: events[i].prospectCount, agentCode: events[i].agentCode, cfCode: events[i].cfCode)
            refreshCounts()
            return events[i]
        }
    }

    func deleteSession(id: UUID) async throws {
        lock.withLock { events.removeAll { $0.id == id }; prospects.removeAll { $0.sessionId == id } }
    }

    func regenerateCode(sessionId: UUID, role: Role) async throws -> SessionSummary {
        try lock.withLock {
            guard let i = events.firstIndex(where: { $0.id == sessionId }) else { throw APIError(status: 404, code: "not_found", message: "") }
            let e = events[i]
            events[i] = SessionSummary(
                session: e.session, prospectCount: e.prospectCount,
                agentCode: role == .agent ? Self.randomCode() : e.agentCode,
                cfCode: role == .conseillerFormation ? Self.randomCode(prefix: "C") : e.cfCode
            )
            return events[i]
        }
    }

    func fetchParticipants(sessionId: UUID) async throws -> [Participant] { lock.withLock { participants } }

    func removeParticipant(sessionId: UUID, participantId: UUID) async throws {
        lock.withLock { participants.removeAll { $0.id == participantId } }
    }

    // MARK: Prospects

    func fetchProspects(sessionId: UUID) async throws -> [Prospect] {
        lock.withLock { prospects.filter { $0.sessionId == sessionId && $0.deletedAt == nil }.sorted { $0.createdAt > $1.createdAt } }
    }

    func createProspect(sessionId: UUID, _ input: ProspectInput) async throws -> Prospect {
        try await Task.sleep(for: .milliseconds(350))
        return lock.withLock {
            let now = Self.iso(Date())
            let p = Prospect(id: UUID(), sessionId: sessionId, prenom: input.prenom, nom: input.nom, email: input.email, telephone: input.telephone, programId: input.programId, niveauActuel: input.niveauActuel, statut: input.statut, notes: input.notes, createdBy: nil, agentNom: displayName, createdAt: now, updatedAt: now, deletedAt: nil)
            prospects.append(p)
            refreshCounts()
            return p
        }
    }

    func updateProspect(id: UUID, _ input: ProspectInput) async throws -> Prospect {
        try await Task.sleep(for: .milliseconds(250))
        return try lock.withLock {
            guard let i = prospects.firstIndex(where: { $0.id == id }) else { throw APIError(status: 404, code: "not_found", message: "") }
            prospects[i].prenom = input.prenom; prospects[i].nom = input.nom; prospects[i].email = input.email
            prospects[i].telephone = input.telephone; prospects[i].programId = input.programId
            prospects[i].niveauActuel = input.niveauActuel; prospects[i].statut = input.statut; prospects[i].notes = input.notes
            prospects[i].updatedAt = Self.iso(Date())
            return prospects[i]
        }
    }

    func archiveProspect(id: UUID) async throws {
        lock.withLock {
            if let i = prospects.firstIndex(where: { $0.id == id }) { prospects[i].deletedAt = Self.iso(Date()) }
            refreshCounts()
        }
    }

    func restoreProspect(id: UUID) async throws {
        lock.withLock {
            if let i = prospects.firstIndex(where: { $0.id == id }) { prospects[i].deletedAt = nil }
            refreshCounts()
        }
    }

    func fetchArchivedProspects() async throws -> [Prospect] {
        lock.withLock { prospects.filter { $0.deletedAt != nil }.sorted { ($0.deletedAt ?? "") > ($1.deletedAt ?? "") } }
    }

    func fetchMyStats() async throws -> MyStats {
        lock.withLock {
            let mine = prospects.filter { $0.agentNom == displayName && $0.deletedAt == nil }
            return MyStats(prospects: mine.count, events: Set(mine.map(\.sessionId)).count, rdv: mine.filter { $0.statut.hasPrefix("Rdv") }.count)
        }
    }
}

extension DemoProspectService {
    /// The seeded programs, readable synchronously (for SwiftUI previews).
    var previewPrograms: [Program] { lock.withLock { programs } }
}
