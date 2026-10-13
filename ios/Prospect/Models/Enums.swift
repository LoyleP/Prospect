// Models/Enums.swift
// Fixed domain enumerations. Programs are per-organization data (Models/Program.swift).
// Color semantics live in StatutBadge.swift (SwiftUI layer).
import Foundation

enum Role: String, CaseIterable, Codable, Sendable {
    case agent               = "agent"
    case conseillerFormation = "conseiller_formation"
    case admin               = "admin"

    var label: String {
        switch self {
        case .agent:               return "Agent"
        case .conseillerFormation: return L("Advisor")
        case .admin:               return L("Administrator")
        }
    }

    var shortLabel: String {
        switch self {
        case .agent:               return "Agent"
        case .conseillerFormation: return L("Advisor")
        case .admin:               return "Admin"
        }
    }

    var summary: String {
        switch self {
        case .agent:               return L("Records and edits prospects.")
        case .conseillerFormation: return L("Views prospects and exports data.")
        case .admin:               return L("Manages events, the team and programs.")
        }
    }
}

/// Lifecycle of an event (the API's `status`).
enum SessionStatut: String, CaseIterable, Codable, Identifiable, Sendable {
    case pasCommence = "pas_commence"
    case enCours     = "en_cours"
    case termine     = "termine"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pasCommence: return L("Not started")
        case .enCours:     return L("In progress")
        case .termine:     return L("Finished")
        }
    }
}

enum NiveauActuel: String, CaseIterable, Codable, Identifiable {
    case avantTerminale = "< Terminale"
    case terminale      = "Terminale"
    case bac1           = "Bac +1"
    case bac2           = "Bac +2"
    case bac3           = "Bac +3"
    case apresBac3      = "> Bac +3"

    var id: String { rawValue }
}

enum Statut: String, CaseIterable, Codable, Identifiable, Comparable {
    case curieux      = "Curieux"
    case interesse    = "Intéressé"
    case rdvInfo      = "Rdv d'info pris"
    case rdvAdmission = "Rdv d'admission pris"

    var id: String { rawValue }

    var order: Int {
        switch self {
        case .curieux:      return 0
        case .interesse:    return 1
        case .rdvInfo:      return 2
        case .rdvAdmission: return 3
        }
    }

    static func <(lhs: Statut, rhs: Statut) -> Bool {
        lhs.order < rhs.order
    }
}
