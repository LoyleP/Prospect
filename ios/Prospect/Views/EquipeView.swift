// Views/EquipeView.swift
// Admin-only: the admin code co-admins use to join, and the organization's admins.
// Agents and conseillers are managed per event (event menu → Codes d'accès).
import SwiftUI

struct EquipeView: View {
    @State private var viewModel = EquipeViewModel()
    @State private var showSettings = false
    @State private var confirmNewCode = false
    @State private var toast: Toast?
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack(alignment: .top) {
                    ScreenHeading(label: appState.currentOrganization?.name ?? "Organisation", title: "Équipe.")
                    IconButton(systemImage: "gearshape", label: "Réglages de l'organisation") { showSettings = true }
                        .accessibilityIdentifier("orgSettingsButton")
                }

                if let code = appState.currentOrganization?.adminCode {
                    NumberedSection(number: "01", title: "Code administrateur") {
                        CodeTicket(
                            title: "Co-administrateurs",
                            detail: "",
                            code: code,
                            shareText: "Rejoignez « \(appState.currentOrganization?.name ?? "") » comme administrateur sur Prospect : créez un compte administrateur puis entrez le code \(code).",
                            onCopy: { copyToPasteboard(code); toast = Toast(message: "Code copié", style: .success) },
                            onRegenerate: { confirmNewCode = true }
                        )
                    }
                }

                NumberedSection(number: "02", title: "Administrateurs") {
                    VStack(spacing: 0) {
                        ForEach(viewModel.admins) { admin in
                            let isSelf = admin.userId == appState.userId
                            HStack(spacing: Space.m) {
                                Monogram(name: admin.displayName, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isSelf ? "\(admin.displayName) (vous)" : admin.displayName)
                                        .font(.textHeadline)
                                        .foregroundStyle(Color.inkPrimary)
                                    Text(admin.email)
                                        .font(.textFootnote)
                                        .foregroundStyle(Color.inkSecondary)
                                }
                                Spacer()
                                if !isSelf {
                                    Button { viewModel.adminToRemove = admin } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(Color.inkTertiary)
                                            .frame(width: 55, height: 55)
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel("Retirer \(admin.displayName)")
                                }
                            }
                            .padding(.vertical, Space.m)
                            Rule()
                        }
                        if viewModel.isLoading && viewModel.admins.isEmpty { SkeletonRow().padding(.vertical, Space.m) }
                    }
                }

            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.l)
            .padding(.bottom, 110)
        }
        .background(PaperBackground())
        .toolbar(.hidden, for: .navigationBar)
        .toast($toast)
        .navigationDestination(isPresented: $showSettings) { OrganizationSettingsView() }
        .confirmationDialog("Générer un nouveau code administrateur ?", isPresented: $confirmNewCode, titleVisibility: .visible) {
            Button("Nouveau code", role: .destructive) {
                Task {
                    if let org = await viewModel.regenerateAdminCode() {
                        appState.apply(org)
                        toast = Toast(message: "Nouveau code généré", style: .success)
                    }
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
    NavigationStack { EquipeView() }
        .environment(AppState.preview(role: .admin))
}
