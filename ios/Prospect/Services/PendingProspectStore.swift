// Services/PendingProspectStore.swift
// Prospects saved while the network was down. They are kept on the phone, shown in the list as
// "en attente", and sent as soon as a request goes through. Each carries its own id, so sending
// one twice (for example after a timeout) never creates a duplicate on the server.
import Foundation
import Observation

@Observable @MainActor
final class PendingProspectStore {
    static let shared = PendingProspectStore()

    struct Item: Codable, Equatable, Identifiable {
        let id: UUID
        let sessionId: UUID
        let input: ProspectInput
        let authorName: String
        let createdAt: String
    }

    private(set) var items: [Item] = []
    private(set) var isFlushing = false
    @ObservationIgnored private let key = "pendingProspects.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        }
    }

    func items(for sessionId: UUID) -> [Item] { items.filter { $0.sessionId == sessionId } }

    /// Stores a prospect for later and returns how it should look in the list meanwhile.
    func enqueue(sessionId: UUID, input: ProspectInput, authorName: String) -> Prospect {
        let id = input.clientId ?? UUID()
        let now = ISO8601DateFormatter().string(from: Date())
        if !items.contains(where: { $0.id == id }) {
            items.append(Item(id: id, sessionId: sessionId, input: input, authorName: authorName, createdAt: now))
            persist()
        }
        return Self.prospect(from: items.first { $0.id == id }!)
    }

    static func prospect(from item: Item) -> Prospect {
        Prospect(id: item.id, sessionId: item.sessionId, prenom: item.input.prenom, nom: item.input.nom,
                 email: item.input.email, telephone: item.input.telephone, programId: item.input.programId,
                 niveauActuel: item.input.niveauActuel, statut: item.input.statut, notes: item.input.notes,
                 createdBy: nil, agentNom: item.authorName, createdAt: item.createdAt, updatedAt: item.createdAt, deletedAt: nil)
    }

    /// For tests and for signing out.
    func removeAll() { items = []; persist() }

    func isPending(_ id: UUID) -> Bool { items.contains { $0.id == id } }

    /// Sends what is waiting. Stops at the first network failure; drops items the server refuses
    /// for good (archived event, invalid data) and returns how many were dropped.
    @discardableResult
    func flush(using service: ProspectServiceProtocol) async -> (sent: [Prospect], dropped: Int) {
        guard !isFlushing, !items.isEmpty else { return ([], 0) }
        isFlushing = true
        defer { isFlushing = false }
        var sent: [Prospect] = []
        var dropped = 0
        for item in items {
            do {
                var input = item.input
                input.clientId = item.id
                sent.append(try await service.createProspect(sessionId: item.sessionId, input))
                items.removeAll { $0.id == item.id }
            } catch let error as APIError where error.status == 0 || error.status == 401 || error.status >= 500 {
                break
            } catch {
                items.removeAll { $0.id == item.id }
                dropped += 1
            }
        }
        persist()
        return (sent, dropped)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }
}
