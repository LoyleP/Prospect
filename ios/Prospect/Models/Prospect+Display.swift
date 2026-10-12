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

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f
    }()

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM · HH:mm"
        return f
    }()

    /// "il y a 5 min" within the last day, "14 nov. · 10:42" otherwise.
    static func friendly(_ string: String, now: Date = Date()) -> String {
        guard let date = parse(string) else { return "" }
        if now.timeIntervalSince(date) < 86_400, date <= now.addingTimeInterval(60) {
            return relative.localizedString(for: date, relativeTo: now)
        }
        return shortDate.string(from: date)
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
