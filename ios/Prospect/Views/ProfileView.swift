// Views/ProfileView.swift
// Who you are here: activity, the programs you follow (conseillers), your organizations,
// and sign-out. Opened from the monogram on the Prospects tab.
import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ProfileViewModel()
    @State private var showLogoutConfirm = false
    @State private var showCreateOrganization = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header

                NumberedSection(number: "01", title: "Activité") {
                    HStack(alignment: .top, spacing: 0) {
                        stat("\(viewModel.totalProspects)", "prospects")
                        stat("\(viewModel.rdvCount)", "RDV")
                        stat("\(Int(viewModel.rdvRate.rounded())) %", "taux")
                    }
                    .opacity(viewModel.isLoading ? 0.35 : 1)
                    .animation(.curve(0.2), value: viewModel.isLoading)
                }

                if let event = appState.participantEvent {
                    NumberedSection(number: "02", title: appState.eventLabel) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.name).font(.textHeadline).foregroundStyle(Color.inkPrimary)
                            Text(appState.currentOrganization?.name ?? "")
                                .font(.textFootnote).foregroundStyle(Color.inkSecondary)
                        }
                    }
                }

                if appState.isParticipant && appState.role == .conseillerFormation && !appState.programs.isEmpty {
                    NumberedSection(number: "03", title: "Mes programmes") {
                        VStack(alignment: .leading, spacing: Space.m) {
                            PillFlowLayout(spacing: Space.s) {
                                ForEach(appState.programs) { p in
                                    ChoiceChip(
                                        title: p.name,
                                        isSelected: appState.currentOrganization?.programIds.contains(p.id) ?? false,
                                        tint: p.swiftUIColor
                                    ) { Task { await toggleProgram(p.id) } }
                                }
                            }

                        }
                    }
                }

                if appState.role == .admin && !appState.isParticipant {
                    NumberedSection(number: "02", title: "Vue en tant que") {
                        VStack(alignment: .leading, spacing: Space.m) {
                            PillFlowLayout(spacing: Space.s) {
                                ForEach(Role.allCases, id: \.self) { r in
                                    ChoiceChip(title: r.shortLabel, isSelected: appState.effectiveRole == r) {
                                        appState.previewRole = r == appState.role ? nil : r
                                    }
                                }
                            }
                            if appState.previewRole != nil {
                                Text("Aperçu : votre rôle réel n'est pas modifié.")
                                    .font(.textFootnote)
                                    .foregroundStyle(Color.accent)
                            }
                        }
                    }

                    NumberedSection(number: "03", title: "Organisations") {
                        VStack(spacing: 0) {
                            ForEach(appState.organizations) { org in
                                let current = org.id == appState.currentOrganization?.id
                                Button {
                                    Haptics.selection()
                                    Task { dismiss(); await appState.selectOrganization(org) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(org.name).font(.textHeadline).foregroundStyle(Color.inkPrimary)
                                            Text(org.role.label).font(.textFootnote).foregroundStyle(Color.inkSecondary)
                                        }
                                        Spacer()
                                        if current { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.accent) }
                                    }
                                    .padding(.horizontal, Space.l)
                                    .frame(minHeight: 60)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(current)
                                Rule().padding(.leading, Space.l)
                            }
                            Button { showCreateOrganization = true } label: {
                                HStack {
                                    Text("Créer ou rejoindre une organisation").font(.textSub.weight(.semibold))
                                    Spacer()
                                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                                }
                                .foregroundStyle(Color.inkPrimary)
                                .padding(.horizontal, Space.l)
                                .frame(minHeight: 55)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                    }
                }

                #if DEBUG
                if appState.role == .admin {
                    NumberedSection(number: "··", title: "Debug") {
                        Toggle(isOn: Binding(
                            get: { LiveActivityManager.shared.isRunning },
                            set: { on in on ? LiveActivityManager.shared.startTest() : LiveActivityManager.shared.end() }
                        )) {
                            Text("Live Activity de test").font(.textSub)
                        }
                    }
                }
                #endif

                Button(appState.isParticipant ? "Quitter l'événement" : "Se déconnecter") { showLogoutConfirm = true }
                    .buttonStyle(.secondary)
                    .padding(.top, Space.s)
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.surfaceBackground)
        .sheet(isPresented: $showCreateOrganization) {
            CreateOrganizationView(isOnboarding: false)
                .presentationBackground(Color.surfaceBackground)
        }
        .alert(appState.isParticipant ? "Quitter l'événement ?" : "Se déconnecter ?", isPresented: $showLogoutConfirm) {
            Button(appState.isParticipant ? "Quitter" : "Se déconnecter") {
                dismiss()
                Task { await appState.signOut() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(appState.isParticipant
                 ? "Pour revenir, il faudra de nouveau le code de l'événement."
                 : "Vous devrez saisir votre mot de passe pour vous reconnecter.")
        }
        .alert("Erreur", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task { await viewModel.load() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.l) {
            Monogram(name: appState.agentNom, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(appState.agentNom)
                    .font(.displayS)
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(2)
                HStack(spacing: Space.s) {
                    BadgeTag(label: appState.role.label, color: appState.role == .admin ? .adminAccent : .info)

                }
            }
            Spacer(minLength: 40)
        }
        .padding(.top, Space.l)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.numeral(30))
                .foregroundStyle(Color.inkPrimary)
                .monospacedDigit()
            Text(label)
                .font(.textCaption.weight(.medium))
                .foregroundStyle(Color.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleProgram(_ id: UUID) async {
        guard var org = appState.currentOrganization else { return }
        if let programs = await viewModel.toggleProgram(id, current: org.programIds) {
            org.programIds = programs
            appState.apply(org)
        }
    }
}

#Preview("Profil — Admin") {
    Text("").sheet(isPresented: .constant(true)) { ProfileView() }
        .environment(AppState.preview(role: .admin))
}
