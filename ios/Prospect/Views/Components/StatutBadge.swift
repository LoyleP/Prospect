// Views/Components/StatutBadge.swift
// Colour semantics for pipeline stages, plus the badge used by the dashboard.
import SwiftUI

extension Statut {
    var color: Color {
        switch self {
        case .curieux:      return .statutCurieux
        case .interesse:    return .statutInteresse
        case .rdvInfo:      return .statutRdvInfo
        case .rdvAdmission: return .statutRdvAdmission
        }
    }
}

struct StatutBadge: View {
    let statut: Statut

    var body: some View {
        StatusStamp(statut: statut)
    }
}
