// Views/EventAccessView.swift
// Admin-only: the event's join codes, one ticket each, and who joined with them.
import SwiftUI

struct EventAccessView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var summary: SessionSummary
    @State private var participants: [Participant] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var roleToRegenerate: Role?
    @State private var participantToRemove: Participant?
    @State private var toast: Toast?
    private let onChange: (SessionSummary) -> Void
    private let service: ProspectServiceProtocol = ProspectService.current

    init(summary: SessionSummary, onChange: @escaping (SessionSummary) -> Void = { _ in }) {
        _summary = State(initialValue: summary)
        self.onChange = onChange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                ScreenHeading(label: summary.name, title: "Codes d'accès.")
                    .padding(.trailing, 44)

                if summary.isArchived {
                    Text("Archivé : ces codes ne fonctionnent plus.")
                        .font(.textFootnote.weight(.semibold))
                        .foregroundStyle(Color.accent)
                }

                NumberedSection(number: "01", title: "Agents") {
                    ticket(.agent, detail: "")
                }
                NumberedSection(number: "02", title: "Conseillers") {
                    ticket(.conseillerFormation, detail: "")
                }

                NumberedSection(number: "03", title: "Présents (\(participants.count))") {
                    if participants.isEmpty && !isLoading {
                        Text("Personne n'a encore rejoint.")
                            .font(.textSub)
                            .foregroundStyle(Color.inkSecondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(participants) { p in
                            HStack(spacing: Space.m) {
                                Monogram(name: p.displayName, size: 38)
                                Text(p.displayName)
                                    .font(.textHeadline)
                                    .foregroundStyle(Color.inkPrimary)
                                Spacer()
                                StatusLabel(text: p.role.shortLabel, color: p.role == .agent ? .inkSecondary : .info, showsDot: false)
                                Button { participantToRemove = p } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color.inkTertiary)
                                        .frame(width: 55, height: 55)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Retirer \(p.displayName)")
                            }
                            .padding(.vertical, Space.s)
                            Rule()
                        }
                    }

                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxl)
        }
        .background(PaperBackground())
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.inkPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.surfaceCard2, in: Circle())
                    .frame(width: 55, height: 55)
                    .contentShape(Rectangle())
            }
            .padding(Space.l)
            .accessibilityLabel("Fermer")
        }
        .toast($toast)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.surfaceBackground)
        .task { await loadParticipants() }
        .refreshable { await loadParticipants() }
        .confirmationDialog(
            "Générer un nouveau code ?",
            isPresented: Binding(get: { roleToRegenerate != nil }, set: { if !$0 { roleToRegenerate = nil } }),
            titleVisibility: .visible
        ) {
            Button("Nouveau code", role: .destructive) {
                if let role = roleToRegenerate { Task { await regenerate(role) } }
            }
        } message: {
            Text("L'ancien code ne fonctionnera plus. Les personnes déjà connectées gardent leur accès.")
        }
        .alert(
            "Retirer \(participantToRemove?.displayName ?? "") ?",
            isPresented: Binding(get: { participantToRemove != nil }, set: { if !$0 { participantToRemove = nil } })
        ) {
            Button("Retirer", role: .destructive) {
                if let p = participantToRemove { Task { await remove(p) } }
            }
            Button("Annuler", role: .cancel) {}
        }
        .alert("Erreur", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func ticket(_ role: Role, detail: String) -> some View {
        let code = summary.code(for: role) ?? "——————"
        return CodeTicket(
            title: "Code \(role.label.lowercased())",
            detail: detail,
            code: code,
            shareText: "Rejoignez « \(summary.name) » sur Prospect en tant que \(role.label.lowercased()) : ouvrez l'app, onglet Code, et entrez \(code).",
            onCopy: { copyToPasteboard(code); toast = Toast(message: "Code copié", style: .success) },
            onRegenerate: { roleToRegenerate = role }
        )
    }

    private func loadParticipants() async {
        isLoading = true
        defer { isLoading = false }
        do {
            participants = try await service.fetchParticipants(sessionId: summary.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func regenerate(_ role: Role) async {
        do {
            summary = try await service.regenerateCode(sessionId: summary.id, role: role)
            onChange(summary)
            toast = Toast(message: "Nouveau code généré", style: .success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ participant: Participant) async {
        participantToRemove = nil
        do {
            try await service.removeParticipant(sessionId: summary.id, participantId: participant.id)
            participants.removeAll { $0.id == participant.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
