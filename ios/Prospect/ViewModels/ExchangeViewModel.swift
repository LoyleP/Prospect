// ViewModels/ExchangeViewModel.swift
// Backs the Collecte (organizer), Envoi (agent) and Réception (conseiller) tab: which event, who sent what, the
// duplicates, and the nearby transfers: the organizer receives, agents send, conseillers ask for the event's data.
import Foundation
import Observation

@Observable
@MainActor
final class ExchangeViewModel {
    var events: [StoredEvent] = []
    var selectedId: UUID?
    var message: String?
    var errorMessage: String?

    /// Organizer: listening for agents and conseillers. Agent / conseiller: the transfer in progress.
    let host = NearbyHost()
    let client = NearbyClient()
    @ObservationIgnored private var pendingCount = 0

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

    func select(_ id: UUID) {
        selectedId = id
        if host.isRunning { startReceiving() }   // advertise the event that is now selected
    }

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

    /// Agent: sends the file to the organizer's phone, nearby. `markSent` runs when the organizer acknowledges it.
    func sendNearby() {
        guard let e = selected, !client.isBusy else { return }
        do {
            let file = try exchange.handoverFile(for: e.id)
            pendingCount = file.count
            let name = store.read { $0.identity?.displayName } ?? ""
            client.sendHandover(file.data, eventId: e.id, name: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Conseiller: asks the organizer for the event's data, nearby. The organizer has to accept.
    func receiveNearby() {
        guard let e = selected, !client.isBusy else { return }
        let name = store.read { $0.identity?.displayName } ?? ""
        client.onEventData = { [weak self] data in
            guard let self else { return false }
            do {
                self.pendingCount = try self.exchange.receiveEventData(data)
                return true
            } catch {
                self.errorMessage = error.localizedDescription
                return false
            }
        }
        client.requestEventData(eventId: e.id, name: name)
    }

    /// Called by the view when `client.state` changes.
    func clientStateChanged(_ state: NearbyClient.State) {
        switch state {
        case .done:
            if exchange.store.read({ $0.identity?.role }) == .conseillerFormation {
                message = L("\(pendingCount) prospects received")
            } else {
                markSent(count: pendingCount)
                message = L("Sent")
            }
            load()
        case .failed(let text):
            errorMessage = text
        default:
            break
        }
    }

    // MARK: Organizer: receiving

    func startReceiving() {
        guard let e = selected, e.isOrganizer else { return }
        host.onHandover = { [weak self] data in
            guard let self else { return Nearby.Ack(ok: false, error: L("Receiving isn't available.")) }
            do {
                let outcome = try self.exchange.importHandover(data)
                self.message = AppState.message(for: outcome)
                self.load()
                return Nearby.Ack(ok: true, added: outcome.merge.added, updated: outcome.merge.updated)
            } catch {
                self.errorMessage = error.localizedDescription
                return Nearby.Ack(ok: false, error: error.localizedDescription)
            }
        }
        host.eventData = { [weak self] in
            guard let self, let id = self.selected?.id else { return nil }
            return try? self.exchange.eventData(for: id)
        }
        host.onNotice = { [weak self] text in self?.message = text }
        host.start(eventId: e.id, displayName: e.organizerName)
        Haptics.tap()
    }

    func stopReceiving() { host.stop() }

    func markSent(count: Int) {
        guard let id = selected?.id else { return }
        exchange.markSent(eventId: id, count: count)
        load()
    }
}
