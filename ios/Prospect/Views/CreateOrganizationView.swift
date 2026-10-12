// Views/CreateOrganizationView.swift
// An admin sets up an organization (name + what its events are called), or joins an existing
// one with the admin code a co-admin shared. Full-screen as onboarding for an account with no
// organization, and a sheet from the profile otherwise.
import SwiftUI

struct CreateOrganizationView: View {
    /// Onboarding: the account has no organization yet.
    let isOnboarding: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private enum Field { case name, label }

    @State private var name = ""
    @State private var eventLabel = "Événement"
    @State private var adminCode = ""
    @State private var showJoin = false
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var shake = 0
    @FocusState private var focused: Field?

    private static let suggestions = ["Événement", "JPO", "Salon", "Forum", "Portes ouvertes"]

    private var cleanName: String { name.trimmingCharacters(in: .whitespaces) }
    private var cleanLabel: String { eventLabel.trimmingCharacters(in: .whitespaces) }
    private var canCreate: Bool { !cleanName.isEmpty && !cleanLabel.isEmpty }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if isOnboarding { Wordmark(size: 28).padding(.top, Space.l) }

                    Text("Votre organisation")
                        .font(.displayXL)
                        .foregroundStyle(Color.inkPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, isOnboarding ? 0 : Space.xl)

                    LabeledField(title: "Nom de l'organisation", isFocused: focused == .name) {
                        TextField("ex. École Horizon", text: $name)
                            .textInputAutocapitalization(.words)
                            .focused($focused, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focused = .label }
                            .accessibilityIdentifier("orgNameField")
                    }

                    labelSection

                    joinSection

                    if let errorText { InlineError(text: errorText) }

                    if isOnboarding {
                        Button("Se déconnecter") { Task { await appState.signOut() } }
                            .buttonStyle(.link)
                            .foregroundStyle(Color.inkSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { createBar }
        .overlay(alignment: .topTrailing) {
            if !isOnboarding {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceCard2, in: Circle())
                        .frame(width: 55, height: 55)
                        .contentShape(Rectangle())
                }
                .padding(Space.l)
                .accessibilityLabel("Fermer")
            }
        }
        .animation(.curve(0.2), value: showJoin)
        .animation(.curve(0.2), value: errorText)
    }

    // MARK: - Pieces

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Vos événements s'appellent")
                .font(.textCaption.weight(.medium))
                .foregroundStyle(Color.inkTertiary)

            PillFlowLayout(spacing: Space.s) {
                ForEach(Self.suggestions, id: \.self) { s in
                    ChoiceChip(title: s, isSelected: eventLabel == s) { eventLabel = s }
                }
            }

            LabeledField(title: "Autre", isFocused: focused == .label) {
                TextField("Événement", text: $eventLabel)
                    .textInputAutocapitalization(.sentences)
                    .focused($focused, equals: .label)
            }

        }
    }

    private var joinSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Rule()
            Button {
                Haptics.selection()
                showJoin.toggle()
            } label: {
                HStack {
                    Text("J'ai un code administrateur")
                        .font(.textSub.weight(.semibold))
                    Spacer()
                    Image(systemName: showJoin ? "minus" : "plus")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Color.inkPrimary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showJoin {
                VStack(alignment: .leading, spacing: Space.m) {
                    CodeEntryField(code: $adminCode, hasError: errorText != nil && showJoin, shakeTrigger: shake)
                    Button("Rejoindre l'organisation") { Task { await join() } }
                        .buttonStyle(.secondary)
                        .disabled(adminCode.count < 6 || isSaving)
                }
                .transition(.opacity)
            }
        }
    }

    private var createBar: some View {
        Button {
            Task { await create() }
        } label: {
            ZStack {
                Text("Créer l'organisation").opacity(isSaving ? 0 : 1)
                if isSaving { ProgressView().tint(Color.onInk) }
            }
        }
        .buttonStyle(.primary)
        .disabled(!canCreate || isSaving)
        .accessibilityIdentifier("createOrgButton")
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
        .background(Color.surfaceBackground.opacity(0.96).ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Actions

    private func create() async {
        await perform {
            try await appState.createOrganization(name: cleanName, eventLabel: cleanLabel)
        }
    }

    private func join() async {
        await perform { try await appState.joinOrganization(adminCode: adminCode) }
    }

    private func perform(_ action: () async throws -> Void) async {
        focused = nil
        isSaving = true
        defer { isSaving = false }
        errorText = nil
        do {
            try await action()
            Haptics.success()
            if !isOnboarding { dismiss() }
        } catch let error as APIError where error.code == "invalid_code" {
            errorText = "Code administrateur invalide."
            adminCode = ""
            shake += 1
            Haptics.error()
        } catch {
            errorText = error.localizedDescription
            Haptics.error()
        }
    }
}

#Preview {
    CreateOrganizationView(isOnboarding: true)
        .environment(AppState.preview())
}
