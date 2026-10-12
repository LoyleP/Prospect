// Font+Prospect.swift
// One family: SF Pro, system font (licensed, native, Dynamic Type aware). No serif, no monospaced fonts.
//   • display — SF Pro Heavy/Bold, for headlines, big numbers and access codes
//   • text    — SF Pro Regular/Semibold, for everything you read and tap; tracked capitals for labels and stamps
import SwiftUI

extension Font {

    // MARK: Display (heavy sans)

    static let displayXL = Font.system(.largeTitle, weight: .semibold)
    static let displayL  = Font.system(.largeTitle, weight: .semibold)
    static let displayM  = Font.system(.title, weight: .semibold)
    static let displayS  = Font.system(.title2, weight: .semibold)
    static let displayXS = Font.system(.title3, weight: .semibold)

    /// A big numeral. Fixed size on purpose: it is a graphic, not running text.
    static func numeral(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: Text (sans)

    static let textHeadline = Font.system(.headline, weight: .medium)
    static let textBody     = Font.system(.body)
    static let textCallout  = Font.system(.callout)
    static let textSub      = Font.system(.subheadline)
    static let textFootnote = Font.system(.footnote)
    static let textCaption  = Font.system(.caption)
    static let textCaption2 = Font.system(.caption2)

    // MARK: Labels & figures (still sans: no monospaced fonts)

    /// Small tracked capitals: section labels, stamps. Callers add `.weight` / `.tracking` / `.textCase`.
    static let labelCaption  = Font.system(.caption)
    static let labelCaption2 = Font.system(.caption2)

    /// Sans with tabular figures: columns of numbers line up without a monospaced face.
    static func figure(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
    static let figureHeadline = Font.system(.headline, weight: .semibold).monospacedDigit()
    static let figureTitle3   = Font.system(.title3).monospacedDigit()
}
