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
    /// Identifies this form's prospect, so saving twice (a double tap) never creates two.
    @ObservationIgnored let clientId = UUID()
    @ObservationIgnored private let authorName: String
    let programs: [Program]
    @ObservationIgnored private let service: ProspectServiceProtocol

    init(mode: ProspectFormMode, programs: [Program], authorName: String = "", service: ProspectServiceProtocol = ProspectService.current) {
        self.mode     = mode
        self.authorName = authorName
        self.programs = programs
        self.service  = service
        switch mode {
        case .create(let session):
            // The last programme used at this event, so a stand's agent does not pick it every time.
            if let saved = UserDefaults.standard.string(forKey: Self.lastProgramKey(session.id)),
               let id = UUID(uuidString: saved), programs.contains(where: { $0.id == id }) { programId = id }
        case .edit(let p):     populate(from: p)
        }
    }

    var navigationTitle: String {
        switch mode {
        case .create: return "Nouveau prospect"
        case .edit:   return "Modifier"
        }
    }

    var emailIsValid: Bool {
        let parts = email.trimmingCharacters(in: .whitespaces).split(separator: "@")
        return parts.count == 2 && parts[1].contains(".")
    }

    var phoneIsValid: Bool {
        let trimmed = telephone.trimmingCharacters(in: .whitespaces)
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: " +-()/."))
        return trimmed.filter(\.isNumber).count >= 6 && trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func lastProgramKey(_ session: UUID) -> String { "lastProgram.\(session.uuidString)" }

    /// A programme is required when the organization has any: it feeds the stats.
    var needsProgram: Bool { !programs.isEmpty && programId == nil }

    var isValid: Bool {
        !needsProgram
            && !prenom.trimmingCharacters(in: .whitespaces).isEmpty
            && !nom.trimmingCharacters(in: .whitespaces).isEmpty
            && emailIsValid
            && phoneIsValid
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
            notes:        trimmedNotes.isEmpty ? nil : trimmedNotes,
            clientId:     { if case .create = mode { return clientId } else { return nil } }()
        )
    }

    func save() async -> Prospect? {
        guard isValid else { return nil }
        isSaving = true
        defer { isSaving = false }

        do {
            switch mode {
            case .create(let session):
                if let programId { UserDefaults.standard.set(programId.uuidString, forKey: Self.lastProgramKey(session.id)) }
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
