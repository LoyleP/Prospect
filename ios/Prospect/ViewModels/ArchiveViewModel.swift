// ViewModels/ArchiveViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class ArchiveViewModel {
    var prospects: [Prospect] = []
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let service: ProspectServiceProtocol

    init(service: ProspectServiceProtocol = ProspectService.current) {
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            prospects = try await service.fetchArchivedProspects()
        } catch {
            errorMessage = L("Couldn't load the archive: \(error.localizedDescription)")
        }
    }

    func restore(_ prospect: Prospect) async {
        do {
            try await service.restoreProspect(id: prospect.id)
            prospects.removeAll { $0.id == prospect.id }
        } catch {
            errorMessage = L("Couldn't restore the prospect: \(error.localizedDescription)")
        }
    }
}
