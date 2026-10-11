// Views/Components/ShareSheet.swift
// Shares a generated file through the iOS share sheet (Files, Mail, AirDrop…).
import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let csvData: Data
    let fileName: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csvData.write(to: tmpURL)
        } catch {
            print("[Prospect] CSV write failed: \(error)")
        }
        let vc = UIActivityViewController(activityItems: [tmpURL], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: tmpURL)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// "Salon d'automne" + "2026-11-14" → "Salon_d'automne_2026-11-14.csv"
func csvFileName(_ parts: String...) -> String {
    parts.joined(separator: "_")
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "/", with: "-") + ".csv"
}
