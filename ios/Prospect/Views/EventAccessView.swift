// Views/EventAccessView.swift
// Admin-only: the event's join codes (agent / conseiller) and who joined with them.
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
    private let onChange: (SessionSummary) -> Void
    private let service: ProspectServiceProtocol = ProspectService.shared

    init(summary: SessionSummary, onChange: @escaping (SessionSummary) -> Void = { _ in }) {
        _summary = State(initialValue: summary)
        self.onChange = onChange
    }

    var body: some View {
        NavigationStack {
            List {
                if summary.isArchived {
                    Section {
                        Label("Archivé : les codes ne permettent plus de rejoindre.", systemImage: "lock")
                            .foregroundStyle(Color.warning)
                    }
                    .themedRowBackground()
                }

                codeSection(role: .agent, footer: "Les agents enregistrent et modifient les prospects.")
                codeSection(role: .conseillerFormation, footer: "Les conseillers consultent les prospects et le tableau de bord.")

                Section {
                    if participants.isEmpty && !isLoading {
                        Text("Personne n'a encore rejoint.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(participants) { p in
                        HStack {
                            Text(p.displayName)
                            Spacer()
                            BadgeTag(label: p.role.shortLabel, color: p.role == .agent ? .roleAgent : .roleCF)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                participantToRemove = p
                            } label: {
                                Label("Retirer", systemImage: "person.badge.minus")
                            }
                        }
                    }
                } header: {
                    Text("Participants (\(participants.count))")
                } footer: {
                    Text("Glissez vers la gauche pour retirer quelqu'un : il perd l'accès immédiatement, ses prospects sont conservés.")
                }
                .themedRowBackground()
            }
            .themedListBackground()
            .themedNavigationBar()
            .navigationTitle("Codes d'accès")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
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
    }

    private func codeSection(role: Role, footer: String) -> some View {
        let code = summary.code(for: role) ?? "—"
        return Section {
            HStack {
                Text(code)
                    .font(.geistMonoTitle3.weight(.bold))
                    .tracking(4)
                    .textSelection(.enabled)
                    .accessibilityLabel("Code \(role.label) : \(code.map(String.init).joined(separator: " "))")
                Spacer()
                ShareLink(item: shareMessage(code: code, role: role)) {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel("Partager le code \(role.label)")
                }
                .buttonStyle(.borderless)
                Button {
                    roleToRegenerate = role
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .accessibilityLabel("Nouveau code \(role.label)")
                }
                .buttonStyle(.borderless)
                .padding(.leading, 12)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Code \(role.label.lowercased())")
        } footer: {
            Text(footer)
        }
        .themedRowBackground()
    }

    private func shareMessage(code: String, role: Role) -> String {
        "Rejoignez « \(summary.name) » sur Prospect en tant que \(role.label.lowercased()) : ouvrez l'app, choisissez « Rejoindre » et entrez le code \(code)."
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

#Preview {
    EventAccessView(summary: SessionSummary(
        session: Session(id: UUID(), name: "Salon de l'étudiant", date: "2026-11-14", isArchived: false,
                         statutSession: .enCours, preRegistered: 0, rdvTargetLow: 0, rdvTargetHigh: 0,
                         programObjectives: [:], createdAt: "2026-10-01T09:00:00.000Z"),
        prospectCount: 3, agentCode: "H4TR9P", cfCode: "W2NQ7D"
    ))
    .environment(AppState.preview())
}
