// Views/DuplicatesView.swift
// Visitors recorded by more than one agent (same email or phone). The organizer archives the extra copy.
import SwiftUI

struct DuplicatesView: View {
    let groups: [[Prospect]]
    var onArchive: (Prospect) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack {
                    Text("Doublons").font(.displayS).foregroundStyle(Color.inkPrimary)
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
                if groups.isEmpty {
                    Text("Aucun doublon.").font(.textSub).foregroundStyle(Color.inkSecondary)
                }
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(spacing: 0) {
                        ForEach(Array(group.enumerated()), id: \.element.id) { index, p in
                            HStack(spacing: Space.m) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(p.fullName).font(.textBody).foregroundStyle(Color.inkPrimary)
                                    Text("\(p.agentNom) · \(p.createdFriendly)").font(.textFootnote).foregroundStyle(Color.inkSecondary)
                                }
                                Spacer()
                                if index > 0 {
                                    Button("Archiver") { Haptics.tap(); onArchive(p) }
                                        .font(.textSub.weight(.medium))
                                        .foregroundStyle(Color.accent)
                                        .frame(minWidth: 55, minHeight: 55)
                                        .contentShape(Rectangle())
                                } else {
                                    Text("Garder").font(.textFootnote).foregroundStyle(Color.inkTertiary)
                                }
                            }
                            .padding(.horizontal, Space.l)
                            .frame(minHeight: 60)
                            if index < group.count - 1 { Rule().padding(.leading, Space.l) }
                        }
                    }
                    .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .presentationDragIndicator(.visible)
    }
}
