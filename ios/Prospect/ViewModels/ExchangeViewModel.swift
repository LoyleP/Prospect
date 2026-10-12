// ViewModels/ExchangeViewModel.swift
// Backs the Collecte (organizer) and Envoi (agent) tab: which event, who sent what, the duplicates,
// importing an agent's file, and building the file an agent sends.
import Foundation
import Observation

@Observable
@MainActor
final class ExchangeViewModel {
    var events: [StoredEvent] = []
    var selectedId: UUID?
    var message: String?
    var errorMessage: String?

    @ObservationIgnored private let exchange: EventExchange
    @ObservationIgnored private var store: LocalStore { exchange.store }

    init(exchange: EventExchange = .current) {
        self.exchange = exchange
    }

    var selected: StoredEvent? { events.first { $0.id == selectedId } ?? events.first }

    func load() {
        events = store.read { $0.events.filter { !$0.isArchived }.sorted { $0.date > $1.date } }
        if selected == nil || !events.contains(where: { $0.id == selectedId }) {
            selectedId = (events.first { $0.status == .enCours } ?? events.first)?.id
        }
    }

    func select(_ id: UUID) { selectedId = id }

    // MARK: Organizer

    var invitationURL: URL? {
        guard let id = selected?.id else { return nil }
        return try? exchange.invitation(for: id).url
    }

    var duplicateGroups: [[Prospect]] {
        guard let e = selected else { return [] }
        return HandoverMerge.duplicateGroups(in: e.prospects)
    }

    func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let outcome = try exchange.importHandover(data)
            message = AppState.message(for: outcome)
            selectedId = exchange.eventId(ofHandover: data) ?? selectedId
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleImportsComplete() {
        guard let e = selected else { return }
        exchange.setImportsComplete(eventId: e.id, !e.importsComplete)
        load()
    }

    func finishEvent() {
        guard let id = selected?.id else { return }
        store.write { state in
            if let i = state.events.firstIndex(where: { $0.id == id }) { state.events[i].status = .termine }
        }
        load()
    }

    func archiveDuplicate(_ prospect: Prospect) {
        store.write { state in
            guard let e = state.events.firstIndex(where: { $0.id == prospect.sessionId }),
                  let p = state.events[e].prospects.firstIndex(where: { $0.id == prospect.id }) else { return }
            state.events[e].prospects[p].deletedAt = ProspectService.iso()
            state.events[e].prospects[p].updatedAt = ProspectService.iso()
        }
        load()
    }

    // MARK: Agent

    /// Prospects recorded on this phone for the selected event, and how many were added since the last send.
    var mineCount: Int { selected?.activeProspects.count ?? 0 }
    var newSinceSend: Int {
        guard let e = selected else { return 0 }
        guard let sent = e.lastSentAt else { return e.activeProspects.count }
        return e.activeProspects.filter { (ISODates.parse($0.createdAt) ?? .distantPast) > sent }.count
    }

    func makeHandover() -> (url: URL, count: Int)? {
        guard let id = selected?.id else { return nil }
        do {
            let file = try exchange.handoverFile(for: id)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.fileName)
            try file.data.write(to: url, options: .atomic)
            return (url, file.count)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func markSent(count: Int) {
        guard let id = selected?.id else { return }
        exchange.markSent(eventId: id, count: count)
        load()
    }
}
