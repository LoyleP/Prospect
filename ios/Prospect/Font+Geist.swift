// Font+Geist.swift
// Programmatic Geist font registration + semantic SwiftUI Font constants.
// Font files (Geist-Variable.ttf, GeistMono-Variable.ttf) must be in the Xcode target's
// Copy Bundle Resources phase — no Info.plist entry needed.
import SwiftUI
import CoreText

extension Font {

    // MARK: - Registration

    static func registerGeistFonts() {
        ["Geist-Variable", "GeistMono-Variable"].forEach { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                print("[Typography] Font file not found: \(name).ttf — add it to the Xcode target.")
                return
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: - Geist (proportional)

    static let geistLargeTitle  = Font.custom("Geist", size: 34, relativeTo: .largeTitle)
    static let geistTitle       = Font.custom("Geist", size: 28, relativeTo: .title)
    static let geistTitle2      = Font.custom("Geist", size: 22, relativeTo: .title2)
    static let geistTitle3      = Font.custom("Geist", size: 20, relativeTo: .title3)
    static let geistHeadline    = Font.custom("Geist", size: 17, relativeTo: .headline).weight(.semibold)
    static let geistBody        = Font.custom("Geist", size: 17, relativeTo: .body)
    static let geistCallout     = Font.custom("Geist", size: 16, relativeTo: .callout)
    static let geistSubheadline = Font.custom("Geist", size: 15, relativeTo: .subheadline)
    static let geistFootnote    = Font.custom("Geist", size: 13, relativeTo: .footnote)
    static let geistCaption     = Font.custom("Geist", size: 12, relativeTo: .caption)
    static let geistCaption2    = Font.custom("Geist", size: 11, relativeTo: .caption2)

    // Hero stat display (large bold number in dashboard)
    static let geistLargeStat   = Font.custom("Geist", size: 52, relativeTo: .largeTitle).weight(.bold)

    // MARK: - Geist Mono (tabular / numeric content)

    static let geistMonoTitle3   = Font.custom("Geist Mono", size: 20, relativeTo: .title3)
    static let geistMonoHeadline = Font.custom("Geist Mono", size: 17, relativeTo: .headline).weight(.semibold)
    static let geistMonoCaption  = Font.custom("Geist Mono", size: 12, relativeTo: .caption)
    static let geistMonoCaption2 = Font.custom("Geist Mono", size: 11, relativeTo: .caption2)
}
