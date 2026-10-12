// Color+Tokens.swift
// Centralized color tokens. Every color in the app should reference this file.
//
// Identity: a guest register. Tailwind gray scale, ink, ONE signal colour (blue).
// Colour meaning is respected: red = error/destructive only, amber = warning, green = success.
// Light and dark are both designed (not inverted): light gray ↔ near-black gray, ink ↔ paper.
// Signal (cobalt) is reserved for "live" and the single most important action on a screen.
import SwiftUI
import UIKit

extension Color {
    /// A colour with explicit light- and dark-mode values.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {

    // MARK: - Neutral scale (kept for older screens)

    static let gray100 = Color(red: 0.953, green: 0.957, blue: 0.965) // #F3F4F6
    static let gray200 = Color(red: 0.898, green: 0.906, blue: 0.922) // #E5E7EB
    static let gray300 = Color(red: 0.820, green: 0.835, blue: 0.855) // #D1D5DB
    static let gray400 = Color(red: 0.612, green: 0.639, blue: 0.686) // #9CA3AF
    static let gray500 = Color(red: 0.420, green: 0.451, blue: 0.498) // #6B7280
    static let gray600 = Color(red: 0.294, green: 0.333, blue: 0.388) // #4B5563
    static let gray700 = Color(red: 0.216, green: 0.255, blue: 0.318) // #374151
    static let gray800 = Color(red: 0.122, green: 0.161, blue: 0.216) // #1F2937
    static let gray900 = Color(red: 0.067, green: 0.094, blue: 0.153) // #111827

    // MARK: - Paper & ink

    /// The page.
    static let surfaceBackground = Color(light: 0xF4F5F8, dark: 0x0B0B0C)
    /// Cards, inputs: slightly lifted from the page.
    static let surfaceCard       = Color(light: 0xFFFFFF, dark: 0x151516)
    /// Recessed / pressed areas, chips at rest.
    static let surfaceCard2      = Color(light: 0xE9EBF0, dark: 0x1F2022)

    /// Text and strokes. Always the same hue, differing only in strength.
    static let inkPrimary   = Color(light: 0x0B0B0C, dark: 0xF2F3F5)
    static let inkSecondary = Color(light: 0x0B0B0C, dark: 0xF2F3F5).opacity(0.6)
    static let inkTertiary  = Color(light: 0x0B0B0C, dark: 0xF2F3F5).opacity(0.52)

    /// Hairlines. Every divider, card border and field outline.
    static let borderSubtle = Color(light: 0x0B0B0C, dark: 0xF2F3F5).opacity(0.08)
    static let rule         = Color(light: 0x0B0B0C, dark: 0xF2F3F5).opacity(0.08)
    /// Stronger line for emphasis (selected field, outlined button).
    static let ruleStrong   = Color(light: 0x0B0B0C, dark: 0xF2F3F5).opacity(0.5)

    /// Text/icons placed on an ink-coloured fill (the paper colour, inverted by mode).
    static let onInk = Color(light: 0xF4F5F8, dark: 0x0B0B0C)

    // MARK: - Signal & semantic

    /// Cobalt blue. "Live", and the one signal action. Blue is the neutral "primary / active" hue:
    /// red is reserved for errors and destructive actions, amber for warnings, green for success.
    static let accent      = Color(light: 0x5E6AD2, dark: 0x7A84E8)
    static let accentDeep  = Color.accent
    /// Text/icons placed on the accent fill (white).
    static let onAccent    = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let success     = Color(light: 0x1E7A57, dark: 0x4CC596)
    static let warning     = Color(light: 0xB27A12, dark: 0xE8B04A)
    static let error       = Color(light: 0xBF3326, dark: 0xFF7A6B)
    static let info        = Color(light: 0x1B6F86, dark: 0x5BC0D8)
    static let adminAccent = Color(light: 0x5A4A8A, dark: 0xB4A5E8)

    // MARK: - Chart targets

    static let targetLow  = Color.inkTertiary
    static let targetHigh = Color.success

    // MARK: - Statut: a neutral-to-positive progression drawn as inks; none of them is red or amber

    static let statutCurieux      = Color(light: 0x6B7280, dark: 0x8A8F98) // gray
    static let statutInteresse    = Color(light: 0x3A3F4B, dark: 0xD0D6E0) // light gray (not amber: amber means warning)
    static let statutRdvInfo      = Color(light: 0x1B6F86, dark: 0x5BC0D8) // teal
    static let statutRdvAdmission = Color(light: 0x1E7A57, dark: 0x4CC596) // green

    // MARK: - Role

    static let roleAgent = Color.inkTertiary
    static let roleCF    = Color.info
    static let roleAdmin = Color.adminAccent

    // MARK: - Helpers

    /// Standard badge background (15% opacity tint).
    static func badgeBg(_ color: Color) -> Color { color.opacity(0.15) }
}
