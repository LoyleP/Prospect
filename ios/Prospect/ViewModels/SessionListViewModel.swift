// ViewModels/SessionListViewModel.swift
// Loads events and handles creation, editing, archiving and deletion (admin).
import Foundation
import Observation

@Observable
@MainActor
final class SessionListViewModel {
    var summaries: [SessionSummary] = []
    var selectedSummary: SessionSummary?
    var isLoading = false
    var errorMessage: String?

    var activeSummaries:   [SessionSummary] { summaries.filter { !$0.isArchived } }
    var archivedSummaries: [SessionSummary] { summaries.filter {  $0.isArchived } }

    // New event sheet
    var showNewSessionSheet = false
    var newSessionName: String = ""
    var newSessionDate: Date = .now
    var newSessionEndsAt: Date?

    var canCreate: Bool {
        !newSessionName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Edit event sheet
    var sessionToEdit: SessionSummary?
    var editSessionName: String = ""
    var editSessionDate: Date = .now
    var editSessionStatut: SessionStatut = .pasCommence
    var editSessionEndsAt: Date?

    var canUpdate: Bool {
        !editSessionName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Delete confirmation
    var sessionToDelete: SessionSummary?

    @ObservationIgnored private let service: ProspectServiceProtocol

    init(service: ProspectServiceProtocol = ProspectService.current) {
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            summaries = try await service.fetchSessionSummaries()
            if let id = selectedSummary?.id, let refreshed = summaries.first(where: { $0.id == id }) {
                selectedSummary = refreshed
            } else {
                selectedSummary = activeSummaries.first(where: { $0.statutSession == .enCours }) ?? activeSummaries.first ?? summaries.first
            }
        } catch {
            errorMessage = L("Couldn't load events: \(error.localizedDescription)")
        }
    }

    func createSession() async {
        guard canCreate else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let created = try await service.createSession(
                name: newSessionName.trimmingCharacters(in: .whitespaces),
                date: newSessionDate
            )
            if let endsAt = newSessionEndsAt {
                _ = try await service.updateSession(id: created.id, SessionPatch(endsAt: endsAt))
            }
            newSessionName = ""
            newSessionDate = .now
            newSessionEndsAt = nil
            showNewSessionSheet = false
            selectedSummary = created
            await load()
        } catch {
            errorMessage = L("Couldn't create: \(error.localizedDescription)")
        }
    }

    func beginEdit(_ summary: SessionSummary) {
        editSessionName   = summary.name
        editSessionDate   = summary.session.displayDate ?? .now
        editSessionStatut = summary.statutSession
        editSessionEndsAt = summary.session.endsAt
        sessionToEdit     = summary
    }

    func commitEdit() async {
        guard let session = sessionToEdit, canUpdate else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await service.updateSession(id: session.id, SessionPatch(
                name: editSessionName.trimmingCharacters(in: .whitespaces),
                date: Session.isoDay(editSessionDate),
                status: editSessionStatut,
                endsAt: editSessionEndsAt
            ))
            sessionToEdit = nil
            await load()
        } catch {
            errorMessage = L("Couldn't edit: \(error.localizedDescription)")
        }
    }

    func confirmDelete() async {
        guard let session = sessionToDelete else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.deleteSession(id: session.id)
            sessionToDelete = nil
            if selectedSummary?.id == session.id { selectedSummary = nil }
            await load()
        } catch {
            errorMessage = L("Couldn't delete: \(error.localizedDescription)")
        }
    }

    func toggleArchive(_ summary: SessionSummary) async {
        do {
            _ = try await service.updateSession(id: summary.id, SessionPatch(isArchived: !summary.isArchived))
            await load()
        } catch {
            errorMessage = L("Couldn't archive: \(error.localizedDescription)")
        }
    }
}
