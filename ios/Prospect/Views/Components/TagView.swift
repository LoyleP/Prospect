// Views/Components/TagView.swift
// Small static labels for list items (role, "Modifié"…): a stamp.
import SwiftUI

/// Small stamp for rows: role, state.
struct BadgeTag: View {
    let label: String
    var color: Color = Color.inkPrimary

    var body: some View {
        StatusLabel(text: label, color: color, showsDot: false)
    }
}
