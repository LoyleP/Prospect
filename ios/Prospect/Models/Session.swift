// Models/Session.swift
// An event (JPO, salon, open day… — each organization names it) as returned by `/orgs/:id/events`.
// `date` is the Postgres DATE as "YYYY-MM-DD".
import Foundation

private let isoDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private let longDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "fr_FR")
    f.dateStyle = .long
    return f
}()

struct Session: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
    let date: String        // "YYYY-MM-DD"
    var isArchived: Bool
    var statutSession: SessionStatut
    var preRegistered: Int
    var rdvTargetLow: Int
    var rdvTargetHigh: Int
    /// Target prospect count per program, keyed by program id.
    var programObjectives: [UUID: Int]
    let createdAt: String

    var displayDate: Date? { isoDayFormatter.date(from: date) }

    var formattedDate: String {
        guard let d = displayDate else { return date }
        return longDateFormatter.string(from: d)
    }

    static func isoDay(_ date: Date) -> String { isoDayFormatter.string(from: date) }
}

/// An event plus its active prospect count, and — for admins only — its join codes.
struct SessionSummary: Identifiable, Equatable, Hashable, Sendable, Decodable {
    let session: Session
    let prospectCount: Int
    var agentCode: String? = nil
    var cfCode: String? = nil

    var id: UUID { session.id }
    var name: String { session.name }
    var date: String { session.date }
    var isArchived: Bool { session.isArchived }
    var statutSession: SessionStatut { session.statutSession }
    var preRegistered: Int { session.preRegistered }
    var rdvTargetLow: Int { session.rdvTargetLow }
    var rdvTargetHigh: Int { session.rdvTargetHigh }
    var programObjectives: [UUID: Int] { session.programObjectives }
    var formattedDate: String { session.formattedDate }
    var asSession: Session { session }

    enum CodingKeys: String, CodingKey {
        case prospectCount = "prospect_count"
        case agentCode     = "agent_code"
        case cfCode        = "cf_code"
    }

    init(session: Session, prospectCount: Int, agentCode: String? = nil, cfCode: String? = nil) {
        self.session = session
        self.prospectCount = prospectCount
        self.agentCode = agentCode
        self.cfCode = cfCode
    }

    init(from decoder: Decoder) throws {
        session = try Session(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prospectCount = try c.decode(Int.self, forKey: .prospectCount)
        agentCode = try c.decodeIfPresent(String.self, forKey: .agentCode)
        cfCode = try c.decodeIfPresent(String.self, forKey: .cfCode)
    }

    /// The join code for a participant role (admins only).
    func code(for role: Role) -> String? {
        switch role {
        case .agent:               return agentCode
        case .conseillerFormation: return cfCode
        case .admin:               return nil
        }
    }
}

extension Session: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, name, date, status
        case isArchived        = "is_archived"
        case preRegistered     = "pre_registered"
        case rdvTargetLow      = "rdv_target_low"
        case rdvTargetHigh     = "rdv_target_high"
        case programObjectives = "program_objectives"
        case createdAt         = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self, forKey: .id)
        name          = try c.decode(String.self, forKey: .name)
        date          = try c.decode(String.self, forKey: .date)
        isArchived    = try c.decode(Bool.self, forKey: .isArchived)
        statutSession = try c.decode(SessionStatut.self, forKey: .status)
        preRegistered = try c.decode(Int.self, forKey: .preRegistered)
        rdvTargetLow  = try c.decode(Int.self, forKey: .rdvTargetLow)
        rdvTargetHigh = try c.decode(Int.self, forKey: .rdvTargetHigh)
        createdAt     = try c.decode(String.self, forKey: .createdAt)
        let raw = try c.decodeIfPresent([String: Int].self, forKey: .programObjectives) ?? [:]
        programObjectives = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }
}

/// Body of `PATCH /events/:id`. Nil fields are left unchanged.
struct SessionPatch: Encodable, Sendable {
    var name: String?
    var date: String?
    var status: SessionStatut?
    var isArchived: Bool?
    var preRegistered: Int?
    var rdvTargetLow: Int?
    var rdvTargetHigh: Int?
    var programObjectives: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case name, date, status
        case isArchived        = "is_archived"
        case preRegistered     = "pre_registered"
        case rdvTargetLow      = "rdv_target_low"
        case rdvTargetHigh     = "rdv_target_high"
        case programObjectives = "program_objectives"
    }
}
