// Views/Components/ProspectRow.swift
// Row showing name, program, statut badge, and registering member.
import SwiftUI

struct ProspectRow: View {
    let prospect: Prospect
    @Environment(AppState.self) private var appState

    private var wasModified: Bool {
        prospect.createdAt != prospect.updatedAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(prospect.fullName)
                    .font(.geistHeadline)

                if wasModified {
                    BadgeTag(label: "Modifié", color: Color.warning)
                }

                Spacer()
                if let s = prospect.statutEnum {
                    StatutBadge(statut: s)
                }
            }
            HStack(spacing: 4) {
                if let program = appState.program(prospect.programId) {
                    Circle()
                        .fill(program.swiftUIColor)
                        .frame(width: 8, height: 8)
                }
                Text(appState.programName(prospect.programId))
                    .font(.geistSubheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "person.fill")
                    .font(.geistCaption)
                    .foregroundStyle(.tertiary)
                Text(prospect.agentNom)
                    .font(.geistCaption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
