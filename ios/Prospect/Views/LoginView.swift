// Views/LoginView.swift
// Two ways in, one calm screen:
//  • Code — agents and conseillers type the event code from their admin, plus their name.
//  • Compte admin — admins sign in (or create an account) with email + password.
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.flow.prospect", category: "auth")

struct LoginView: View {
    @Environment(AppState.self) private var appState

    enum Mode: Hashable { case join, admin }
    private enum Field { case name, email, password, adminName }

    @State private var mode: Mode = .join
    @State private var isCreatingAccount = false
    @State private var code = ""
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var adminName = ""
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var shake = 0
    @State private var showPassword = false
    @State private var keyboardUp = false
    @FocusState private var focused: Field?

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        switch mode {
        case .join:
            return code.count == 6 && !trimmed(name).isEmpty
        case .admin:
            let parts = trimmed(email).split(separator: "@")
            let emailOK = parts.count == 2 && parts[1].contains(".")
            if isCreatingAccount { return emailOK && password.count >= 8 && !trimmed(adminName).isEmpty }
            return emailOK && !password.isEmpty
        }
    }

    private var headline: String {
        switch mode {
        case .join:  return "Rejoindre un événement"
        case .admin: return isCreatingAccount ? "Créer un compte" : "Espace administrateur"
        }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    Wordmark(size: 28)
                        .padding(.top, Space.l)

                    Text(headline)
                        .font(keyboardUp ? .displayM : .displayXL)
                        .foregroundStyle(Color.inkPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(headline)
                        .transition(.opacity)

                    UnderlineTabs(options: [Mode.join, .admin], selection: $mode) { $0 == .join ? "Code" : "Compte admin" }
                        .accessibilityIdentifier("loginModePicker")

                    Group {
                        switch mode {
                        case .join:  joinFields
                        case .admin: adminFields
                        }
                    }
                    .transition(.opacity)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .animation(.curve(0.22), value: mode)
        .animation(.curve(0.22), value: isCreatingAccount)
        .animation(.curve(0.2), value: errorText)
        .animation(.curve(0.25), value: keyboardUp)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .onChange(of: mode) { errorText = nil }
        .task(id: appState.loginIntent) { applyIntent() }
    }

    // MARK: - Pieces

    private var joinFields: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Code")
                    .font(.textCaption.weight(.medium))
                    .foregroundStyle(Color.inkTertiary)
                CodeEntryField(code: $code, hasError: errorText != nil && mode == .join, shakeTrigger: shake) {
                    focused = .name
                }
                .accessibilityIdentifier("codeField")
            }

            LabeledField(title: "Votre nom", isFocused: focused == .name) {
                TextField("Prénom Nom", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .focused($focused, equals: .name)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
            }

        }
    }

    @ViewBuilder
    private var adminFields: some View {
        VStack(spacing: Space.m) {
            if isCreatingAccount {
                LabeledField(title: "Votre nom", isFocused: focused == .adminName) {
                    TextField("Prénom Nom", text: $adminName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($focused, equals: .adminName)
                        .submitLabel(.next)
                        .onSubmit { focused = .email }
                }
                .transition(.opacity)
            }
            LabeledField(title: "Email", isFocused: focused == .email, hasError: errorText != nil && focused == nil && mode == .admin) {
                TextField("vous@exemple.com", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
            }
            LabeledField(title: isCreatingAccount ? "Mot de passe · 8 caractères min." : "Mot de passe", isFocused: focused == .password) {
                HStack {
                    Group {
                        if showPassword {
                            TextField("Mot de passe", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Mot de passe", text: $password)
                        }
                    }
                    .textContentType(isCreatingAccount ? .newPassword : .password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Text(showPassword ? "Masquer" : "Afficher")
                            .font(.textCaption.weight(.semibold))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(minWidth: 55, minHeight: 55)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(showPassword ? "Masquer le mot de passe" : "Afficher le mot de passe")
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Space.m) {
            if let errorText { InlineError(text: errorText) }

            Button {
                Task { await submit() }
            } label: {
                ZStack {
                    Text(mode == .join ? "Rejoindre" : (isCreatingAccount ? "Créer mon compte" : "Se connecter"))
                        .opacity(isWorking ? 0 : 1)
                    if isWorking { ProgressView().tint(Color.onInk) }
                }
            }
            .buttonStyle(.primary)
            .disabled(isWorking || !canSubmit)
            .accessibilityIdentifier("loginSubmit")

            if mode == .admin {
                Button(isCreatingAccount ? "J'ai déjà un compte" : "Créer un compte administrateur") {
                    isCreatingAccount.toggle()
                    errorText = nil
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("toggleCreateAccount")
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
        .background(Color.surfaceBackground.opacity(0.96).ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Actions

    private func applyIntent() {
        guard let intent = appState.loginIntent else { return }
        switch intent {
        case .join:          mode = .join; isCreatingAccount = false
        case .admin:         mode = .admin; isCreatingAccount = false
        case .createAccount: mode = .admin; isCreatingAccount = true
        }
        appState.loginIntent = nil
    }

    private func submit() async {
        guard canSubmit, !isWorking else { return }
        focused = nil
        isWorking = true
        defer { isWorking = false }
        errorText = nil
        do {
            switch mode {
            case .join:
                try await AuthService.shared.join(code: code, displayName: trimmed(name))
            case .admin where isCreatingAccount:
                try await AuthService.shared.signUp(email: trimmed(email).lowercased(), password: password, displayName: trimmed(adminName))
            case .admin:
                try await AuthService.shared.logIn(email: trimmed(email).lowercased(), password: password)
            }
            Haptics.success()
            password = ""
            appState.phase = .loading   // LaunchView loads the account / event
        } catch let error as APIError {
            logger.error("Sign-in failed: \(error.code, privacy: .public)")
            switch (error.status, error.code) {
            case (401, "invalid_code"):        errorText = "Code invalide, ou événement terminé."; code = ""; shake += 1
            case (401, "invalid_credentials"): errorText = "Email ou mot de passe incorrect."; shake += 1
            case (409, "email_taken"):         errorText = "Un compte existe déjà avec cet email."
            default:                           errorText = error.localizedDescription
            }
            Haptics.error()
        } catch {
            errorText = error.localizedDescription
            Haptics.error()
        }
    }
}

#Preview("Rejoindre") {
    LoginView()
        .environment(AppState.preview())
}
