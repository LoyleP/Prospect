// Models/Prospect+Display.swift
// Presentation helpers for prospects: dates, relative times, short names.
import Foundation

enum ISODates {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string)
    }

    private static let relative = PerLanguage<RelativeDateTimeFormatter> { language in
        let f = RelativeDateTimeFormatter()
        f.locale = language.locale
        f.unitsStyle = .short
        return f
    }

    private static let shortDate = PerLanguage<DateFormatter> { language in
        let f = DateFormatter()
        f.locale = language.locale
        f.dateFormat = language == .fr ? "d MMM · HH:mm" : "MMM d · HH:mm"
        return f
    }

    /// "5 min ago" within the last day, "Nov 14 · 10:42" otherwise (in French, "il y a 5 min" and "14 nov. · 10:42").
    static func friendly(_ string: String, now: Date = Date()) -> String {
        guard let date = parse(string) else { return "" }
        if now.timeIntervalSince(date) < 86_400, date <= now.addingTimeInterval(60) {
            return relative.value.localizedString(for: date, relativeTo: now)
        }
        return shortDate.value.string(from: date)
    }
}

extension Prospect {
    var createdFriendly: String { ISODates.friendly(createdAt) }
    var wasModified: Bool { createdAt != updatedAt }

    /// "Camille Martin" → "Camille M."
    var agentShortName: String {
        let parts = agentNom.split(separator: " ")
        guard parts.count > 1, let initial = parts.last?.first else { return agentNom }
        return "\(parts[0]) \(initial)."
    }
}
