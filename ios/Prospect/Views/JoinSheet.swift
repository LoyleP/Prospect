// Views/JoinSheet.swift
// An agent already set up joins another event: scan its QR code or paste the link.
import SwiftUI

struct JoinSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""
    @State private var errorText: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack {
                Text(L("Join")).font(.displayS).foregroundStyle(Color.inkPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceCard2, in: Circle())
                        .frame(width: 55, height: 55)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L("Close"))
            }
            QRScannerView { code in handle(code) }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            LabeledField(title: L("Link"), isFocused: focused, hasError: errorText != nil) {
                TextField("prospect://join?…", text: $pasted)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onChange(of: pasted) { _, text in if text.count > 12 { handle(text) } }
            }
            if let errorText { InlineError(text: errorText) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .presentationDragIndicator(.visible)
    }

    private func handle(_ text: String) {
        guard let invitation = Invitation(text: text) else {
            errorText = L("This code isn't a Prospect invitation.")
            return
        }
        do {
            try appState.join(invitation)
            appState.importMessage = L("Joined: \(invitation.name)")
            dismiss()
            appState.epoch += 1
        } catch {
            errorText = error.localizedDescription
        }
    }
}
