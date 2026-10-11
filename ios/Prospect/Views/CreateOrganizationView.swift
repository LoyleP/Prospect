// Views/CreateOrganizationView.swift
// Admins create a new organization (they become its admin), or join an existing one
// with the admin code a co-admin shared. Shown as onboarding for an admin account with
// no organization yet, and from the profile otherwise.
import SwiftUI

struct CreateOrganizationView: View {
    /// Onboarding: the account has no organization yet, so offer sign-out too.
    let isOnboarding: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var eventLabel = "Événement"
    @State private var adminCode = ""
    @State private var isSaving = false
    @State private var errorText: String?

    private static let labelSuggestions = ["Événement", "JPO", "Salon", "Forum", "Portes ouvertes"]

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !eventLabel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Organisation") {
                    TextField("Nom (ex. École Horizon)", text: $name)
                        .textInputAutocapitalization(.words)
                }
                .themedRowBackground()

                Section {
                    TextField("Nom de vos événements", text: $eventLabel)
                    PillFlowLayout(spacing: 8) {
                        ForEach(Self.labelSuggestions, id: \.self) { suggestion in
                            Toggle(suggestion, isOn: Binding(
                                get: { eventLabel == suggestion },
                                set: { if $0 { eventLabel = suggestion } }
                            ))
                            .toggleStyle(FilterToggleStyle())
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Vos événements s'appellent…")
                } footer: {
                    Text("Utilisé dans toute l'app. Modifiable plus tard dans les réglages.")
                }
                .listRowBackground(Color.surfaceBackground)

                Section {
                    Button {
                        Task { await create() }
                    } label: {
                        Text("Créer l'organisation").frame(maxWidth: .infinity)
                    }
                    .disabled(!canCreate || isSaving)
                }
                .themedRowBackground()

                Section {
                    TextField("Code administrateur", text: $adminCode)
                        .font(.geistMonoHeadline)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Rejoindre") { Task { await join() } }
                        .disabled(adminCode.trimmingCharacters(in: .whitespaces).count < 6 || isSaving)
                } header: {
                    Text("Ou rejoindre une organisation existante")
                } footer: {
                    Text("Un administrateur trouve ce code dans l'onglet Équipe.")
                }
                .themedRowBackground()

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(Color.error)
                    }
                    .themedRowBackground()
                }

                if isOnboarding {
                    Section {
                        Button("Se déconnecter", role: .destructive) {
                            Task { await appState.signOut() }
                        }
                    }
                    .themedRowBackground()
                }
            }
            .themedListBackground()
            .themedNavigationBar()
            .navigationTitle(isOnboarding ? "Votre organisation" : "Nouvelle organisation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                }
                if isSaving {
                    ToolbarItem(placement: .confirmationAction) { ProgressView() }
                }
            }
        }
    }

    private func create() async {
        await perform {
            try await appState.createOrganization(
                name: name.trimmingCharacters(in: .whitespaces),
                eventLabel: eventLabel.trimmingCharacters(in: .whitespaces)
            )
        }
    }

    private func join() async {
        await perform { try await appState.joinOrganization(adminCode: adminCode.trimmingCharacters(in: .whitespaces)) }
    }

    private func perform(_ action: () async throws -> Void) async {
        isSaving = true
        defer { isSaving = false }
        errorText = nil
        do {
            try await action()
            if !isOnboarding { dismiss() }
        } catch let error as APIError where error.code == "invalid_code" {
            errorText = "Code administrateur invalide."
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    CreateOrganizationView(isOnboarding: true)
        .environment(AppState.preview())
}
