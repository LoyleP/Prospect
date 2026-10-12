// Utilities/DashboardCSVExporter.swift
// Generates a UTF-8 BOM CSV of aggregated dashboard stats for an event.
import Foundation

enum DashboardCSVExporter {

    static func generate(
        session: Session,
        total: Int,
        byProgram: [ProgramCount],
        byStatut: [StatutCount],
        byAgent: [AgentCount],
        closing: [ClosingCount] = [],
        programName: (UUID?) -> String
    ) -> Data {
        var rows: [String] = []

        let totalProgram = byProgram.reduce(0) { $0 + $1.count }

        // Header
        rows += [
            escape("Tableau de bord — \(session.name) — \(session.formattedDate)"),
            "",
            // Résumé
            row("RÉSUMÉ", ""),
            row("Total prospects", "\(total)"),
            "",
            // Par programme
            row("PAR PROGRAMME", "Prospects", "Pourcentage")
        ]
        for item in byProgram {
            let pct = totalProgram > 0
                ? String(format: "%.1f%%", Double(item.count) / Double(totalProgram) * 100)
                : "0%"
            rows.append(row(programName(item.programId), "\(item.count)", pct))
        }

        rows += [
            "",
            row("PAR STATUT", "Prospects")
        ]
        for item in byStatut {
            rows.append(row(item.statut.exportLabel, "\(item.count)"))
        }

        rows += [
            "",
            row("PAR MEMBRE", "Prospects")
        ]
        for item in byAgent {
            rows.append(row(item.agentNom, "\(item.count)"))
        }

        if !closing.isEmpty {
            rows += [
                "",
                row("CLOSING", "Programme", "Rdv d'information", "Rdv d'admission", "Total")
            ]
            for item in closing {
                rows.append(row(item.cfNom, programName(item.programId), "\(item.rdvInfo)", "\(item.rdvAdmission)", "\(item.total)"))
            }
        }

        let csv = rows.joined(separator: "\n")
        let bom = "\u{FEFF}"
        return (bom + csv).data(using: .utf8) ?? Data()
    }

    private static func row(_ values: String...) -> String {
        values.map(escape).joined(separator: ";")
    }

    private static func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
