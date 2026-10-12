// Views/InvitationSheet.swift
// The organizer's invitation: a QR code agents scan with Prospect, and a link to send instead.
import SwiftUI

struct InvitationCard: View {
    let url: URL
    let eventName: String

    var body: some View {
        VStack(spacing: Space.l) {
            QRCodeView(text: url.absoluteString, size: 220)
            ShareLink(item: url, subject: Text(eventName), message: Text("Rejoins « \(eventName) » sur Prospect")) {
                Label("Partager le lien", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.l)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }
}

/// Opened from the Prospects screen (the QR button): the invitation of the event being shown.
struct InvitationSheet: View {
    let eventId: UUID
    let eventName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack {
                Text("Inviter").font(.displayS).foregroundStyle(Color.inkPrimary)
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
                .accessibilityLabel("Fermer")
            }
            if let url = try? appState.exchange.invitation(for: eventId).url {
                InvitationCard(url: url, eventName: eventName)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .presentationDragIndicator(.visible)
    }
}
