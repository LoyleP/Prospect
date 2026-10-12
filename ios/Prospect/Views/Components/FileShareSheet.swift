// Views/Components/FileShareSheet.swift
// Shares a generated file through the iOS share sheet (AirDrop, Messages, Mail, Files…) and reports whether
// the person actually completed an action, so the app only marks a handover as sent when it was.
import SwiftUI

struct FileShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
            try? FileManager.default.removeItem(at: url)
        }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
