// ViewModels/EquipeViewModel.swift
// Admin team screen: the organization's admins and its admin code.
import Foundation
import Observation

@Observable
@MainActor
final class EquipeViewModel {
    var admins: [Admin] = []
    var isLoading = false
    var errorMessage: String?
    var adminToRemove: Admin?

    @ObservationIgnored private let service: ProspectServiceProtocol

    init(service: ProspectServiceProtocol = ProspectService.current) {
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            admins = try await service.fetchAdmins()
        } catch {
            errorMessage = "Impossible de charger l'équipe : \(error.localizedDescription)"
        }
    }

    func remove(_ admin: Admin) async {
        adminToRemove = nil
        do {
            try await service.removeAdmin(userId: admin.userId)
            admins.removeAll { $0.id == admin.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns the organization with its new admin code.
    func regenerateAdminCode() async -> Organization? {
        do {
            return try await service.regenerateAdminCode()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
