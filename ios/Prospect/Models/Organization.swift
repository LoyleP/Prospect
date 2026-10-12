// Models/Organization.swift
// The person's local workspace on this phone: their name, whether they organize or only record, and what
// they call events. Kept as a type so screens can read it from AppState. Nothing here is shared or synced.
import Foundation

struct Organization: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// What this person calls events ("Événement", "JPO", "Salon"…).
    var eventLabel: String
    var role: Role
    var displayName: String
    var programIds: [UUID]
}
