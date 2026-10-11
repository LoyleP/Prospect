// Models/Program.swift
// A program (formation, filière, product line…) an organization offers. Admins edit the list.
import SwiftUI

struct Program: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var color: String      // "#RRGGBB"
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case sortOrder = "sort_order"
    }

    /// Colours offered in the program editor.
    static let palette = [
        "#3366E6", "#2EC7BF", "#9440D9", "#F2D11A", "#F28019",
        "#33B859", "#142E8C", "#66B8F2", "#99E08C", "#FAED8C",
    ]
}

extension Program {
    var swiftUIColor: Color { Color(hex: color) ?? .gray400 }

    /// White or black — whichever has higher contrast against `color`.
    /// WCAG relative luminance: L = 0.2126R + 0.7152G + 0.0722B (linearised).
    var labelColor: Color {
        guard let (r, g, b) = Color.rgbComponents(hex: color) else { return .white }
        func linearise(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let L = 0.2126 * linearise(r) + 0.7152 * linearise(g) + 0.0722 * linearise(b)
        return L > 0.179 ? .black : .white
    }
}

extension Color {
    static func rgbComponents(hex: String) -> (Double, Double, Double)? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    init?(hex: String) {
        guard let (r, g, b) = Color.rgbComponents(hex: hex) else { return nil }
        self.init(red: r, green: g, blue: b)
    }
}
