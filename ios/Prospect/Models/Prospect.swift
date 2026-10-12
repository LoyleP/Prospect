// Models/Prospect.swift
// Prospect model plus the body sent on create/update.
// Swift names are kept from the original app; CodingKeys map them to the API's snake_case.
import Foundation

struct Prospect: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let sessionId: UUID
    var prenom: String
    var nom: String
    var email: String
    var telephone: String
    var programId: UUID?
    var niveauActuel: String
    var statut: String
    var notes: String?
    let createdBy: UUID?
    /// Display name of the member who registered the prospect.
    var agentNom: String
    let createdAt: String
    var updatedAt: String
    var deletedAt: String?

    var fullName: String { "\(prenom) \(nom)" }
    var statutEnum: Statut? { Statut(rawValue: statut) }

    enum CodingKeys: String, CodingKey {
        case id, email, notes
        case sessionId    = "event_id"
        case prenom       = "first_name"
        case nom          = "last_name"
        case telephone    = "phone"
        case programId    = "program_id"
        case niveauActuel = "education_level"
        case statut       = "status"
        case createdBy    = "created_by"
        case agentNom     = "created_by_name"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
        case deletedAt    = "deleted_at"
    }
}

/// Body of `POST /events/:id/prospects` and `PATCH /prospects/:id`.
struct ProspectInput: Codable, Sendable, Equatable {
    let prenom: String
    let nom: String
    let email: String
    let telephone: String
    let programId: UUID?
    let niveauActuel: String
    let statut: String
    let notes: String?
    /// Chosen by the app when the form opens. Sending it again (a retry) never creates a duplicate.
    var clientId: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case email, notes
        case clientId     = "id"
        case prenom       = "first_name"
        case nom          = "last_name"
        case telephone    = "phone"
        case programId    = "program_id"
        case niveauActuel = "education_level"
        case statut       = "status"
    }

    // Always send program_id and notes, even when nil, so they can be cleared.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(prenom, forKey: .prenom)
        try c.encode(nom, forKey: .nom)
        try c.encode(email, forKey: .email)
        try c.encode(telephone, forKey: .telephone)
        try c.encode(programId, forKey: .programId)
        try c.encode(niveauActuel, forKey: .niveauActuel)
        try c.encode(statut, forKey: .statut)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(clientId, forKey: .clientId)
    }
}
