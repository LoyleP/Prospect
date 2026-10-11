// Models/Organization.swift
// An organization as seen by the signed-in person: includes their role and display name in it.
// Admins also receive `adminCode`, which co-admins enter to join.
import Foundation

struct Organization: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// What this organization calls its events ("Événement", "JPO", "Salon"…).
    var eventLabel: String
    var role: Role
    var displayName: String
    var programIds: [UUID]
    var adminCode: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, role
        case eventLabel  = "event_label"
        case displayName = "display_name"
        case programIds  = "program_ids"
        case adminCode   = "admin_code"
    }
}

/// Response of `GET /me`: an admin account, or a participant of one event.
enum MeResponse: Decodable, Sendable {
    case admin(user: AdminUser, organizations: [Organization])
    case participant(participant: ParticipantProfile, organization: Organization, event: SessionSummary)

    struct AdminUser: Decodable, Sendable {
        let id: UUID
        let email: String
        let displayName: String
        enum CodingKeys: String, CodingKey {
            case id, email
            case displayName = "display_name"
        }
    }

    struct ParticipantProfile: Decodable, Sendable {
        let id: UUID
        let displayName: String
        let role: Role
        enum CodingKeys: String, CodingKey {
            case id, role
            case displayName = "display_name"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, user, organizations, participant, organization, event
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if try c.decode(String.self, forKey: .kind) == "participant" {
            self = .participant(
                participant: try c.decode(ParticipantProfile.self, forKey: .participant),
                organization: try c.decode(Organization.self, forKey: .organization),
                event: try c.decode(SessionSummary.self, forKey: .event)
            )
        } else {
            self = .admin(
                user: try c.decode(AdminUser.self, forKey: .user),
                organizations: try c.decode([Organization].self, forKey: .organizations)
            )
        }
    }
}
