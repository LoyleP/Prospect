// Color+Tokens.swift
// Centralized color tokens. Every color in the app should reference this file.
import SwiftUI

extension Color {

    // MARK: - Surface / Tailwind Gray 100–900

    static let gray100 = Color(red: 0.953, green: 0.957, blue: 0.965) // #F3F4F6
    static let gray200 = Color(red: 0.898, green: 0.906, blue: 0.922) // #E5E7EB
    static let gray300 = Color(red: 0.820, green: 0.835, blue: 0.855) // #D1D5DB
    static let gray400 = Color(red: 0.612, green: 0.639, blue: 0.686) // #9CA3AF
    static let gray500 = Color(red: 0.420, green: 0.451, blue: 0.498) // #6B7280
    static let gray600 = Color(red: 0.294, green: 0.333, blue: 0.388) // #4B5563
    static let gray700 = Color(red: 0.216, green: 0.255, blue: 0.318) // #374151
    static let gray800 = Color(red: 0.122, green: 0.161, blue: 0.216) // #1F2937
    static let gray900 = Color(red: 0.067, green: 0.094, blue: 0.153) // #111827

    // MARK: - Surface Semantic
    // Dark-only surface hierarchy. gray200/300 are near-white and intentionally NOT
    // used here — they don't provide subtle contrast against dark backgrounds.

    static let surfaceBackground = Color.gray900 // App/List/Form base background
    static let surfaceCard       = Color.gray800 // Section/card/row background
    static let surfaceCard2      = Color.gray700 // Nested/secondary surface
    static let borderSubtle      = Color.gray700 // Dividers, hairlines on dark surfaces

    // MARK: - Semantic

    static let accent    = Color.blue
    static let success   = Color.green
    static let warning   = Color.orange
    static let error     = Color.red
    static let info      = Color.teal
    static let adminAccent = Color.purple

    // MARK: - Chart targets

    static let targetLow  = Color.gray500
    static let targetHigh = Color.success

    // MARK: - Statut

    static let statutCurieux      = Color.gray400
    static let statutInteresse    = Color.accent
    static let statutRdvInfo      = Color.warning
    static let statutRdvAdmission = Color.success

    // MARK: - Role

    static let roleAgent = Color.gray500
    static let roleCF    = Color.accent
    static let roleAdmin = Color.adminAccent

    // MARK: - Helpers

    /// Standard badge background (15% opacity tint).
    static func badgeBg(_ color: Color) -> Color { color.opacity(0.15) }
}
