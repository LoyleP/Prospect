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
    var errorMessage: String?

    @ObservationIgnored private let service: ProspectServiceProtocol

    init(service: ProspectServiceProtocol = ProspectService.current) {
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
            errorMessage = L("Couldn't load the profile: \(error.localizedDescription)")
        }
    }
}
