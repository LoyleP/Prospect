// ViewModels/ProspectListViewModel.swift
// Owns the prospect list for an event. While the list is on screen it re-fetches every few
// seconds so prospects added on other phones appear without a manual refresh.
import Foundation
import Observation

@Observable @MainActor
final class ProspectListViewModel {
    /// Delay between two refreshes while the list is visible.
    static let pollInterval: Duration = .seconds(5)

    let session: Session
    let isReadOnly: Bool

    var prospects: [Prospect] = []
    var isLoading = false
    var errorMessage: String?
    var searchText: String = ""
    var filterStatuts: Set<Statut> = []
    var filterPrograms: Set<UUID> = []
    var filterNiveaux: Set<NiveauActuel> = []
    var filterAgents: Set<String> = []

    @ObservationIgnored private let service: ProspectServiceProtocol

    var filteredProspects: [Prospect] {
        prospects.filter { p in
            let matchesSearch = searchText.isEmpty
                || p.fullName.localizedCaseInsensitiveContains(searchText)
                || p.agentNom.localizedCaseInsensitiveContains(searchText)
                || p.email.localizedCaseInsensitiveContains(searchText)
            let matchesStatut  = filterStatuts.isEmpty  || filterStatuts.contains  { $0.rawValue == p.statut }
            let matchesProgram = filterPrograms.isEmpty || p.programId.map(filterPrograms.contains) == true
            let matchesNiveau  = filterNiveaux.isEmpty  || filterNiveaux.contains  { $0.rawValue == p.niveauActuel }
            let matchesAgent   = filterAgents.isEmpty   || filterAgents.contains(p.agentNom)
            return matchesSearch && matchesStatut && matchesProgram && matchesNiveau && matchesAgent
        }
    }

    var hasActiveFilters: Bool {
        !filterStatuts.isEmpty || !filterPrograms.isEmpty || !filterNiveaux.isEmpty || !filterAgents.isEmpty
    }

    var agentNames: [String] {
        Array(Set(prospects.map { $0.agentNom })).sorted()
    }

    func clearFilters() {
        filterStatuts  = []
        filterPrograms = []
        filterNiveaux  = []
        filterAgents   = []
    }

    init(session: Session, isReadOnly: Bool, service: ProspectServiceProtocol = ProspectService.current) {
        self.session    = session
        self.isReadOnly = isReadOnly
        self.service    = service
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            apply(try await service.fetchProspects(sessionId: session.id))
            if session.statutSession == .enCours {
                LiveActivityManager.shared.start(session: session, prospects: prospects)
            }
        } catch {
            errorMessage = "Impossible de charger les prospects : \(error.localizedDescription)"
        }
    }

    /// Initial load, then refreshes until the calling task is cancelled
    /// (SwiftUI cancels `.task` when the view disappears).
    func loadAndPoll() async {
        await load()
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled else { break }
            // Silent refresh: a failed poll keeps the current list and retries next tick.
            await flushPending()
            if let fresh = try? await service.fetchProspects(sessionId: session.id) {
                apply(fresh)
            }
        }
    }

    /// Sends prospects saved while offline. Called on every poll and when the network returns.
    func flushPending() async {
        let store = PendingProspectStore.shared
        guard !store.items.isEmpty else { return }
        let result = await store.flush(using: service)
        if result.dropped > 0 {
            errorMessage = "\(result.dropped) prospect\(result.dropped > 1 ? "s" : "") enregistré\(result.dropped > 1 ? "s" : "") hors connexion n'ont pas pu être envoyés (événement archivé ou données refusées)."
        }
        if !result.sent.isEmpty, let fresh = try? await service.fetchProspects(sessionId: session.id) { apply(fresh) }
    }

    private func apply(_ serverList: [Prospect]) {
        // Still-pending prospects stay visible at the top until the server has them.
        let known = Set(serverList.map(\.id))
        let pending = PendingProspectStore.shared.items(for: session.id)
            .filter { !known.contains($0.id) }
            .map(PendingProspectStore.prospect(from:))
        let fresh = pending + serverList
        guard fresh != prospects else { return }
        prospects = fresh
        if session.statutSession == .enCours {
            Task { await LiveActivityManager.shared.update(prospects: fresh) }
        }
    }

    func upsertLocally(_ prospect: Prospect) {
        if let idx = prospects.firstIndex(where: { $0.id == prospect.id }) {
            prospects[idx] = prospect
        } else {
            prospects.insert(prospect, at: 0)
        }
    }

    // MARK: - Archive

    func archiveProspect(_ prospect: Prospect) async {
        do {
            try await service.archiveProspect(id: prospect.id)
            prospects.removeAll { $0.id == prospect.id }
            if session.statutSession == .enCours {
                await LiveActivityManager.shared.update(prospects: prospects)
            }
        } catch {
            errorMessage = "Impossible d'archiver le prospect : \(error.localizedDescription)"
        }
    }
}
