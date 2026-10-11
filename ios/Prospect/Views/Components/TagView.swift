// Views/Components/TagView.swift
// Unified tag components used across the app.
import SwiftUI

// MARK: - BadgeTag (list items — small, non-interactive)

/// Small capsule badge for list rows: statut, role, "Modifié".
struct BadgeTag: View {
    let label: String
    var color: Color = Color.accent

    var body: some View {
        Text(label)
            .font(.geistCaption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.badgeBg(color))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - FilterTag (sheets, settings — interactive, toggle-driven)

/// Interactive pill for filter sheets and settings. Use via FilterToggleStyle.
/// Default: label + 10 padding. Active: label + checkmark.circle.fill, 8 gap, 10 padding.
