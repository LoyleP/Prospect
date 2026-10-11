// Views/ProfileView.swift
import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ProfileViewModel()
    @State private var showLogoutConfirm = false
    @State private var showCreateOrganization = false

    var body: some View {
        NavigationStack {
            List {
                // Identity section
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.accent)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(appState.agentNom)
                                .font(.geistTitle3.weight(.bold))
                            if let email = appState.email {
                                Text(email)
                                    .font(.geistCaption)
                                    .foregroundStyle(.secondary)
                            }
                            BadgeTag(
                                label: appState.role.label,
                                color: appState.role == .admin ? Color.warning : Color.accent
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                .themedRowBackground()

                // Stats section
                Section("Activité") {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        LabeledContent("Prospects enregistrés") {
                            Text("\(viewModel.totalProspects)")
                                .font(.geistMonoHeadline)
                        }
                        LabeledContent("RDVs obtenus") {
                            Text("\(viewModel.rdvCount)")
                                .font(.geistMonoHeadline)
                        }
                        LabeledContent("Taux RDV") {
                            Text("\(Int(viewModel.rdvRate.rounded()))%")
                                .font(.geistMonoHeadline)
                        }
                        LabeledContent("\(appState.eventLabel) : participations") {
                            Text("\(viewModel.sessionCount)")
                                .font(.geistMonoHeadline)
                        }
                    }
                }
                .themedRowBackground()

                // Role preview — admin only
                if appState.role == .admin {
                    Section {
                        PillFlowLayout(spacing: 8) {
                            ForEach(Role.allCases, id: \.self) { r in
                                Toggle(r.shortLabel, isOn: Binding(
                                    get: { appState.effectiveRole == r },
                                    set: { isOn in
                                        if isOn {
                                            appState.previewRole = r == appState.role ? nil : r
                                        }
                                    }
                                ))
                                .toggleStyle(FilterToggleStyle())
                                .animation(nil, value: appState.effectiveRole)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Vue en tant que")
                    } footer: {
                        if appState.previewRole != nil {
                            Text("Prévisualisation — votre rôle réel n'est pas modifié.")
                                .foregroundStyle(Color.warning)
                        }
                    }
                    .listRowBackground(Color.surfaceBackground) // inactive pills (gray800) need contrast against the row
                }

                // Live Activity test — admin only
                if appState.role == .admin {
                    Section {
                        Toggle(isOn: Binding(
                            get: { LiveActivityManager.shared.isRunning },
                            set: { isOn in
                                if isOn { LiveActivityManager.shared.startTest() }
                                else { LiveActivityManager.shared.end() }
                            }
                        )) {
                            Label("Live Activity", systemImage: "dot.radiowaves.left.and.right")
                        }
                    } header: {
                        Text("Tests")
                    } footer: {
                        Text("Simule une Live Activity avec des données fictives.")
                    }
                    .themedRowBackground()
                }

                // Programs a conseiller follows (dashboard closing stats)
                if appState.isParticipant && appState.role == .conseillerFormation && !appState.programs.isEmpty {
                    Section("Mes programmes") {
                        PillFlowLayout(spacing: 8) {
                            ForEach(appState.programs) { p in
                                Toggle(p.name, isOn: Binding(
                                    get: { appState.currentOrganization?.programIds.contains(p.id) ?? false },
                                    set: { _ in Task { await toggleProgram(p.id) } }
                                ))
                                .toggleStyle(FilterToggleStyle())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.surfaceBackground) // inactive pills (gray800) need contrast against the row
                }

                // Organizations (admin accounts)
                if !appState.isParticipant {
                Section {
                    ForEach(appState.organizations) { org in
                        Button {
                            Task {
                                dismiss()
                                await appState.selectOrganization(org)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(org.name).foregroundStyle(.primary)
                                    Text(org.role.label)
                                        .font(.geistCaption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if org.id == appState.currentOrganization?.id {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accent)
                                }
                            }
                        }
                        .disabled(org.id == appState.currentOrganization?.id)
                    }
                    Button {
                        showCreateOrganization = true
                    } label: {
                        Label("Créer une organisation", systemImage: "plus")
                    }
                } header: {
                    Text("Organisations")
                }
                .themedRowBackground()
                }

                if let event = appState.participantEvent {
                    Section("\(appState.eventLabel)") {
                        LabeledContent("Nom", value: event.name)
                        LabeledContent("Organisation", value: appState.currentOrganization?.name ?? "")
                    }
                    .themedRowBackground()
                }

                // Logout section
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label(appState.isParticipant ? "Quitter l'événement" : "Se déconnecter",
                              systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                .themedRowBackground()
            }
            .themedListBackground()
            .themedNavigationBar()
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)
                    }
                }
            }
            .alert(appState.isParticipant ? "Quitter l'événement ?" : "Se déconnecter ?", isPresented: $showLogoutConfirm) {
                Button(appState.isParticipant ? "Quitter" : "Se déconnecter", role: .destructive) {
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
            .sheet(isPresented: $showCreateOrganization) {
                CreateOrganizationView(isOnboarding: false)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggleProgram(_ id: UUID) async {
        guard var org = appState.currentOrganization else { return }
        if let programs = await viewModel.toggleProgram(id, current: org.programIds) {
            org.programIds = programs
            appState.apply(org)
        }
    }
}

#Preview("Profile — Admin") {
    Text("Tap profile button")
        .sheet(isPresented: .constant(true)) {
            NavigationStack {
                ProfileView()
            }
        }
        .environment(AppState.preview(role: .admin))
}
