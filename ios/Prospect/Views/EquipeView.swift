// Views/EquipeView.swift
// Admin-only: the organization's admins, the admin code co-admins use to join,
// and access to the organization settings. Agents and conseillers are managed per event
// (Prospects tab → ⋯ → Codes d'accès).
import SwiftUI

struct EquipeView: View {
    @State private var viewModel = EquipeViewModel()
    @State private var showSettings = false
    @State private var confirmNewCode = false
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                HStack {
                    Text(appState.currentOrganization?.adminCode ?? "—")
                        .font(.geistMonoTitle3.weight(.bold))
                        .tracking(4)
                        .textSelection(.enabled)
                    Spacer()
                    if let code = appState.currentOrganization?.adminCode {
                        ShareLink(item: "Rejoignez « \(appState.currentOrganization?.name ?? "") » comme administrateur sur Prospect : créez un compte administrateur puis entrez le code \(code).") {
                            Image(systemName: "square.and.arrow.up")
                                .accessibilityLabel("Partager le code administrateur")
                        }
                        .buttonStyle(.borderless)
                    }
                    Button { confirmNewCode = true } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .accessibilityLabel("Nouveau code administrateur")
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 12)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Code administrateur")
            } footer: {
                Text("Donne les droits d'administration complets. À ne partager qu'avec vos co-administrateurs.")
            }
            .themedRowBackground()

            Section("Administrateurs") {
                ForEach(viewModel.admins) { admin in
                    let isSelf = admin.userId == appState.userId
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isSelf ? "\(admin.displayName) (vous)" : admin.displayName)
                            .font(.geistHeadline)
                        Text(admin.email)
                            .font(.geistCaption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !isSelf {
                            Button(role: .destructive) {
                                viewModel.adminToRemove = admin
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            .themedRowBackground()

            Section {
                Label("Les agents et conseillers rejoignent un événement avec ses codes : Prospects → ⋯ → Codes d'accès.", systemImage: "info.circle")
                    .font(.geistFootnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
        }
        .themedListBackground()
        .navigationTitle("Équipe")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .accessibilityLabel("Réglages de l'organisation")
                }
                .accessibilityIdentifier("orgSettingsButton")
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.admins.isEmpty { ProgressView() }
        }
        .navigationDestination(isPresented: $showSettings) {
            OrganizationSettingsView()
        }
        .confirmationDialog("Générer un nouveau code administrateur ?", isPresented: $confirmNewCode, titleVisibility: .visible) {
            Button("Nouveau code", role: .destructive) {
                Task {
                    if let org = await viewModel.regenerateAdminCode() { appState.apply(org) }
                }
            }
        } message: {
            Text("L'ancien code ne fonctionnera plus. Les administrateurs actuels gardent leur accès.")
        }
        .alert(
            "Retirer \(viewModel.adminToRemove?.displayName ?? "") ?",
            isPresented: Binding(get: { viewModel.adminToRemove != nil }, set: { if !$0 { viewModel.adminToRemove = nil } })
        ) {
            Button("Retirer", role: .destructive) {
                if let admin = viewModel.adminToRemove { Task { await viewModel.remove(admin) } }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette personne perdra l'accès à l'organisation.")
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
        .refreshable { await viewModel.load() }
    }
}

#Preview("Équipe — Admin") {
    NavigationStack {
        EquipeView()
    }
    .environment(AppState.preview(role: .admin))
}
