// Views/Components/ProspectRow.swift
// One line, Linear style: stage ring, name, and the programme on the right.
import SwiftUI

struct ProspectRow: View {
    let prospect: Prospect
    var showsStatus = true
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: Space.m) {
            if showsStatus, let s = prospect.statutEnum { StatusRing(statut: s) }
            Text(prospect.fullName)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.inkPrimary)
                .lineLimit(1)
            Spacer(minLength: Space.s)
            if let program = appState.program(prospect.programId) {
                HStack(spacing: 6) {
                    Circle().fill(program.swiftUIColor).frame(width: 7, height: 7)
                    Text(program.name)
                        .font(.textFootnote)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 130, alignment: .trailing)
            }
        }
        .frame(minHeight: 55)
        .contentShape(Rectangle())
    }
}
