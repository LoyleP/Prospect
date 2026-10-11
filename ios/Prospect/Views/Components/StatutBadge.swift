// Views/Components/StatutBadge.swift
// Reusable color-coded badge for pipeline stage display.
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
        BadgeTag(label: statut.rawValue, color: statut.color)
    }
}
