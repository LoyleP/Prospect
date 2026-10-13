// Utilities/CSVExporter.swift
// Generates a UTF-8 BOM CSV from a prospect array.
// The BOM prefix ensures correct encoding detection in Excel; ";" is Excel's separator in French locales.
import Foundation

enum CSVExporter {
    static func columnHeaders(eventLabel: String) -> [String] {
        [
            L("First name"),
            L("Last name"),
            "Email",
            L("Phone"),
            L("Program"),
            L("Current level"),
            L("Status"),
            "Notes",
            L("Recorded by"),
            eventLabel,
            L("Date recorded"),
        ]
    }

    static func generate(
        prospects: [Prospect],
        sessionName: String,
        eventLabel: String,
        programName: (UUID?) -> String
    ) -> Data {
        var rows: [String] = [columnHeaders(eventLabel: eventLabel).map(escape).joined(separator: ";")]

        let isoParser = ISO8601DateFormatter()
        isoParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()

        let displayFormatter = DateFormatter()
        displayFormatter.locale = Language.current.locale
        displayFormatter.dateFormat = Language.current == .fr ? "dd/MM/yyyy HH:mm" : "yyyy-MM-dd HH:mm"

        for p in prospects {
            let date = isoParser.date(from: p.createdAt) ?? isoFallback.date(from: p.createdAt)
            let row = [
                p.prenom,
                p.nom,
                p.email,
                p.telephone,
                programName(p.programId),
                p.niveauActuel,
                Statut(rawValue: p.statut)?.exportLabel ?? p.statut,
                p.notes ?? "",
                p.agentNom,
                sessionName,
                date.map(displayFormatter.string(from:)) ?? p.createdAt,
            ].map(escape).joined(separator: ";")

            rows.append(row)
        }

        let csv = rows.joined(separator: "\n")
        let bom = "\u{FEFF}"                        // UTF-8 BOM
        return (bom + csv).data(using: .utf8) ?? Data()
    }

    /// Wraps a field in double quotes and escapes any internal double quotes (RFC 4180).
    static func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
