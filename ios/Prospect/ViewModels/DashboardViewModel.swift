// ViewModels/DashboardViewModel.swift
// Loads prospects for a selected event and computes all dashboard stats.
import Foundation
import Observation

struct ProgramCount: Identifiable {
    let programId: UUID?
    let count: Int
    var id: String { programId?.uuidString ?? "none" }
}

struct StatutCount: Identifiable {
    let statut: Statut
    let count: Int
    var id: String { statut.rawValue }
}

struct AgentCount: Identifiable {
    let agentNom: String
    let count: Int
    var id: String { agentNom }
}

struct ClosingCount: Identifiable {
    let cfNom: String
    let programId: UUID
    let rdvInfo: Int
    let rdvAdmission: Int
    var id: String { "\(cfNom)|\(programId)" }
    var total: Int { rdvInfo + rdvAdmission }
}

struct HourCount: Identifiable {
    let hour: Int
    let count: Int
    var id: Int { hour }
}

@Observable
@MainActor
final class DashboardViewModel {
    var sessions: [SessionSummary]         = []
    var archivedSessions: [SessionSummary] = []
    var selectedSession: SessionSummary?
    var prospects: [Prospect]              = []
    /// Conseillers of the selected event (admins only), for the closing stats.
    var cfParticipants: [Participant]      = []
    /// The organization's programs, provided by the view (for ordering and names).
    var programs: [Program]                = []
    var isLoading = false
    var errorMessage: String?
    var lastUpdatedAt: Date?

    @ObservationIgnored private let service: ProspectServiceProtocol

    init(service: ProspectServiceProtocol = ProspectService.current) {
        self.service = service
    }

    // MARK: - Filters

    var filterPrograms: Set<UUID> = []
    var filterStatuts: Set<Statut> = []
    var filterNiveaux: Set<NiveauActuel> = []
    var filterAgents: Set<String> = []

    var hasActiveFilters: Bool {
        !filterPrograms.isEmpty || !filterStatuts.isEmpty || !filterNiveaux.isEmpty || !filterAgents.isEmpty
    }

    func clearFilters() {
        filterPrograms = []
        filterStatuts  = []
        filterNiveaux  = []
        filterAgents   = []
    }

    var agentNames: [String] {
        Array(Set(prospects.map { $0.agentNom })).sorted()
    }

    var filteredProspects: [Prospect] {
        prospects.filter { p in
            let matchesProgram = filterPrograms.isEmpty || p.programId.map(filterPrograms.contains) == true
            let matchesStatut  = filterStatuts.isEmpty  || filterStatuts.contains  { $0.rawValue == p.statut }
            let matchesNiveau  = filterNiveaux.isEmpty  || filterNiveaux.contains  { $0.rawValue == p.niveauActuel }
            let matchesAgent   = filterAgents.isEmpty   || filterAgents.contains(p.agentNom)
            return matchesProgram && matchesStatut && matchesNiveau && matchesAgent
        }
    }

    // MARK: - Computed stats (all use filteredProspects)

    var totalProspects: Int { filteredProspects.count }

    var rdvCount: Int {
        filteredProspects.filter {
            $0.statut == Statut.rdvInfo.rawValue || $0.statut == Statut.rdvAdmission.rawValue
        }.count
    }

    var rdvRate: Double {
        guard totalProspects > 0 else { return 0 }
        return Double(rdvCount) / Double(totalProspects) * 100
    }

    var preRegistered: Int  { selectedSession?.preRegistered ?? 0 }
    var rdvTargetLow: Int   { selectedSession?.rdvTargetLow  ?? 0 }
    var rdvTargetHigh: Int  { selectedSession?.rdvTargetHigh ?? 0 }
    var hasRdvTargets: Bool { rdvTargetLow > 0 || rdvTargetHigh > 0 }
    // noShowCount is event-level — always uses the full prospect count
    var noShowCount: Int    { max(0, preRegistered - prospects.count) }

    var byProgram: [ProgramCount] {
        let groups = Dictionary(grouping: filteredProspects, by: { $0.programId })
        return groups.map { ProgramCount(programId: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var byStatut: [StatutCount] {
        Statut.allCases.map { s in
            StatutCount(statut: s, count: filteredProspects.filter { $0.statut == s.rawValue }.count)
        }
    }

    /// Registrations per clock hour between the first and the last one: when the rush happened.
    var arrivals: [HourCount] {
        let calendar = Calendar.current
        let hours = filteredProspects.compactMap { p in ISODates.parse(p.createdAt).map { calendar.component(.hour, from: $0) } }
        guard let first = hours.min(), let last = hours.max() else { return [] }
        let counts = Dictionary(grouping: hours, by: { $0 }).mapValues(\.count)
        return (first...last).map { HourCount(hour: $0, count: counts[$0] ?? 0) }
    }

    var peakHour: HourCount? { arrivals.max { $0.count < $1.count } }

    var byAgent: [AgentCount] {
        let groups = Dictionary(grouping: filteredProspects, by: { $0.agentNom })
        return groups.map { AgentCount(agentNom: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var closing: [ClosingCount] {
        let singleProgram: UUID? = filterPrograms.count == 1 ? filterPrograms.first : nil
        return cfParticipants.flatMap { cf in
            cf.programIds
                .filter { singleProgram == nil || $0 == singleProgram }
                .map { programId in
                    let inSection    = filteredProspects.filter { $0.programId == programId }
                    let rdvInfo      = inSection.filter { $0.statut == Statut.rdvInfo.rawValue }.count
                    let rdvAdmission = inSection.filter { $0.statut == Statut.rdvAdmission.rawValue }.count
                    return ClosingCount(cfNom: cf.displayName, programId: programId, rdvInfo: rdvInfo, rdvAdmission: rdvAdmission)
                }
        }
        .sorted { $0.total > $1.total }
    }

    /// Closing stats grouped by program, in the organization's program order.
    var closingByProgram: [(program: Program, items: [ClosingCount])] {
        let grouped = Dictionary(grouping: closing, by: { $0.programId })
        return programs.compactMap { program in
            grouped[program.id].map { (program: program, items: $0.sorted { $0.total > $1.total }) }
        }
    }

    func loadSessions() async {
        do {
            let fetchedSessions = try await service.fetchSessionSummaries()
            sessions         = fetchedSessions.filter { !$0.isArchived }
            archivedSessions = fetchedSessions.filter { $0.isArchived }
            // Default to the event in progress, fall back to the most recent one
            if let id = selectedSession?.id, let refreshed = fetchedSessions.first(where: { $0.id == id }) {
                selectedSession = refreshed
            } else {
                selectedSession = sessions.first(where: { $0.statutSession == .enCours }) ?? sessions.first
            }
            if let s = selectedSession {
                await loadProspects(for: s)
            }
        } catch {
            errorMessage = "Erreur de chargement : \(error.localizedDescription)"
        }
    }

    func selectSession(_ summary: SessionSummary) async {
        selectedSession = summary
        clearFilters()
        await loadProspects(for: summary)
    }

    private func loadProspects(for summary: SessionSummary) async {
        isLoading = true
        defer { isLoading = false }
        do {
            prospects = try await service.fetchProspects(sessionId: summary.id)
            // Join codes are only sent to admins; only they can list participants.
            cfParticipants = summary.agentCode == nil ? [] :
                ((try? await service.fetchParticipants(sessionId: summary.id)) ?? [])
                    .filter { $0.role == .conseillerFormation }
            lastUpdatedAt = Date()
        } catch {
            errorMessage = "Impossible de charger les données : \(error.localizedDescription)"
        }
    }
}
