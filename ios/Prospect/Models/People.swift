// Models/People.swift
// People with access to an organization: admins (accounts) and event participants (code + name).
import Foundation

/// An admin of the current organization.
struct Admin: Codable, Identifiable, Sendable, Equatable, Hashable {
    let userId: UUID
    let email: String
    let displayName: String
    let lastSeenAt: String?
    let createdAt: String

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case email
        case userId      = "user_id"
        case displayName = "display_name"
        case lastSeenAt  = "last_seen_at"
        case createdAt   = "created_at"
    }
}

/// Someone who joined an event with its agent or conseiller code.
struct Participant: Codable, Identifiable, Sendable, Equatable, Hashable {
    let id: UUID
    let displayName: String
    let role: Role
    var programIds: [UUID]
    let lastSeenAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, role
        case displayName = "display_name"
        case programIds  = "program_ids"
        case lastSeenAt  = "last_seen_at"
        case createdAt   = "created_at"
    }
}
