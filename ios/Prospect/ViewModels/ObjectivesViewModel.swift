// ViewModels/ObjectivesViewModel.swift
// Allows admins to set objectives for a specific event.
import Foundation
import Observation

@Observable
@MainActor
final class ObjectivesViewModel {
    private(set) var session: SessionSummary

    var preRegistered: Int
    var rdvTargetLow: Int
    var rdvTargetHigh: Int
    var programObjectives: [UUID: Int]

    private var savedPreRegistered: Int
    private var savedRdvTargetLow: Int
    private var savedRdvTargetHigh: Int
    private var savedProgramObjectives: [UUID: Int]

    var hasChanges: Bool {
        preRegistered != savedPreRegistered
            || rdvTargetLow != savedRdvTargetLow
            || rdvTargetHigh != savedRdvTargetHigh
            || programObjectives != savedProgramObjectives
    }
    var isSaving = false
    var errorMessage: String?
    var saveSuccess = false

    @ObservationIgnored private let service: ProspectServiceProtocol

    init(session: SessionSummary, service: ProspectServiceProtocol = ProspectService.shared) {
        self.session            = session
        self.service            = service
        preRegistered           = session.preRegistered
        rdvTargetLow            = session.rdvTargetLow
        rdvTargetHigh           = session.rdvTargetHigh
        programObjectives       = session.programObjectives
        savedPreRegistered      = session.preRegistered
        savedRdvTargetLow       = session.rdvTargetLow
        savedRdvTargetHigh      = session.rdvTargetHigh
        savedProgramObjectives  = session.programObjectives
    }

    func objective(for program: Program) -> Int {
        programObjectives[program.id] ?? 0
    }

    func setObjective(_ value: Int, for program: Program) {
        if value <= 0 {
            programObjectives.removeValue(forKey: program.id)
        } else {
            programObjectives[program.id] = value
        }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            session = try await service.updateSession(id: session.id, SessionPatch(
                preRegistered: preRegistered,
                rdvTargetLow: rdvTargetLow,
                rdvTargetHigh: rdvTargetHigh,
                programObjectives: Dictionary(uniqueKeysWithValues: programObjectives.map { ($0.key.uuidString.lowercased(), $0.value) })
            ))
            savedPreRegistered     = preRegistered
            savedRdvTargetLow      = rdvTargetLow
            savedRdvTargetHigh     = rdvTargetHigh
            savedProgramObjectives = programObjectives
            saveSuccess = true
        } catch {
            errorMessage = "Impossible de sauvegarder : \(error.localizedDescription)"
        }
    }
}
