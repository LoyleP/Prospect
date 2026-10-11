// ViewModels/ProspectFormViewModel.swift
// Manages form state and handles both create and update paths.
import Foundation
import Observation

enum ProspectFormMode {
    case create(session: Session)
    case edit(Prospect)
}

@Observable
@MainActor
final class ProspectFormViewModel {
    var prenom: String       = ""
    var nom: String          = ""
    var email: String        = ""
    var telephone: String    = ""
    var programId: UUID?
    var niveauActuel: NiveauActuel = .terminale
    var statut: Statut       = .curieux
    var notes: String        = ""

    var isSaving = false
    var errorMessage: String?

    let mode: ProspectFormMode
    let programs: [Program]
    @ObservationIgnored private let service: ProspectServiceProtocol

    init(mode: ProspectFormMode, programs: [Program], service: ProspectServiceProtocol = ProspectService.shared) {
        self.mode     = mode
        self.programs = programs
        self.service  = service
        switch mode {
        case .create:          programId = programs.first?.id
        case .edit(let p):     populate(from: p)
        }
    }

    var navigationTitle: String {
        switch mode {
        case .create: return "Nouveau prospect"
        case .edit:   return "Modifier"
        }
    }

    var isValid: Bool {
        let trimmedPrenom    = prenom.trimmingCharacters(in: .whitespaces)
        let trimmedNom       = nom.trimmingCharacters(in: .whitespaces)
        let trimmedEmail     = email.trimmingCharacters(in: .whitespaces)
        let trimmedTelephone = telephone.trimmingCharacters(in: .whitespaces)

        guard !trimmedPrenom.isEmpty,
              !trimmedNom.isEmpty,
              !trimmedEmail.isEmpty,
              !trimmedTelephone.isEmpty else { return false }

        let emailParts = trimmedEmail.split(separator: "@")
        guard emailParts.count == 2, emailParts[1].contains(".") else { return false }

        let allowedPhoneChars = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: " +-()/."))
        guard trimmedTelephone.filter(\.isNumber).count >= 6,
              trimmedTelephone.unicodeScalars.allSatisfy({ allowedPhoneChars.contains($0) }) else { return false }

        return true
    }

    private func populate(from p: Prospect) {
        prenom       = p.prenom
        nom          = p.nom
        email        = p.email
        telephone    = p.telephone
        programId    = p.programId
        niveauActuel = NiveauActuel(rawValue: p.niveauActuel) ?? .terminale
        statut       = Statut(rawValue: p.statut) ?? .curieux
        notes        = p.notes ?? ""
    }

    var input: ProspectInput {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProspectInput(
            prenom:       prenom.trimmingCharacters(in: .whitespaces),
            nom:          nom.trimmingCharacters(in: .whitespaces),
            email:        email.trimmingCharacters(in: .whitespaces),
            telephone:    telephone.trimmingCharacters(in: .whitespaces),
            programId:    programId,
            niveauActuel: niveauActuel.rawValue,
            statut:       statut.rawValue,
            notes:        trimmedNotes.isEmpty ? nil : trimmedNotes
        )
    }

    func save() async -> Prospect? {
        guard isValid else { return nil }
        isSaving = true
        defer { isSaving = false }

        do {
            switch mode {
            case .create(let session):
                return try await service.createProspect(sessionId: session.id, input)
            case .edit(let existing):
                return try await service.updateProspect(id: existing.id, input)
            }
        } catch {
            errorMessage = "Impossible d'enregistrer le prospect : \(error.localizedDescription)"
            return nil
        }
    }
}
