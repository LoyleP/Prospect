// ViewModels/ProfileViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class ProfileViewModel {
    private(set) var totalProspects: Int = 0
    private(set) var sessionCount: Int = 0
    private(set) var rdvCount: Int = 0
    private(set) var isLoading = false
    var isSavingPrograms = false
    var errorMessage: String?

    @ObservationIgnored private let service: ProspectServiceProtocol

    init(service: ProspectServiceProtocol = ProspectService.shared) {
        self.service = service
    }

    var rdvRate: Double {
        guard totalProspects > 0 else { return 0 }
        return Double(rdvCount) / Double(totalProspects) * 100
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let stats = try await service.fetchMyStats()
            totalProspects = stats.prospects
            sessionCount   = stats.events
            rdvCount       = stats.rdv
        } catch {
            errorMessage = "Impossible de charger le profil : \(error.localizedDescription)"
        }
    }

    /// Adds or removes one of the participant's own programs; returns the new list on success.
    func toggleProgram(_ programId: UUID, current: [UUID]) async -> [UUID]? {
        var updated = current
        if let idx = updated.firstIndex(of: programId) {
            updated.remove(at: idx)
        } else {
            updated.append(programId)
        }
        isSavingPrograms = true
        defer { isSavingPrograms = false }
        do {
            try await service.updateMe(displayName: nil, programIds: updated)
            return updated
        } catch {
            errorMessage = "Impossible de mettre à jour les programmes : \(error.localizedDescription)"
            return nil
        }
    }
}
