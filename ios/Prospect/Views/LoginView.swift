// Views/LoginView.swift
// Two ways in:
//  • Rejoindre — agents and conseillers type the event code from their admin plus their name.
//  • Administrateur — admins sign in (or create an account) with email + password.
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.flow.prospect", category: "auth")

struct LoginView: View {
    @Environment(AppState.self) private var appState

    private enum Mode: String, CaseIterable, Identifiable {
        case join = "Rejoindre"
        case admin = "Administrateur"
        var id: String { rawValue }
    }

    private enum Field { case code, name, email, password, adminName }

    @State private var mode: Mode = .join
    @State private var isCreatingAccount = false
    @State private var code = ""
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var adminName = ""
    @State private var isWorking = false
    @State private var errorText: String?
    @FocusState private var focused: Field?

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        switch mode {
        case .join:
            return trimmed(code).count >= 6 && !trimmed(name).isEmpty
        case .admin:
            let parts = trimmed(email).split(separator: "@")
            let emailOK = parts.count == 2 && parts[1].contains(".")
            if isCreatingAccount {
                return emailOK && password.count >= 8 && !trimmed(adminName).isEmpty
            }
            return emailOK && !password.isEmpty
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accent)
                    Text("Bienvenue sur Prospect")
                        .font(.geistTitle2.weight(.bold))
                    Text(mode == .join
                         ? "Entrez le code donné par votre responsable"
                         : (isCreatingAccount ? "Créez votre compte administrateur" : "Connectez-vous à votre espace administrateur"))
                        .font(.geistSubheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 72)

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { errorText = nil }

                VStack(alignment: .leading, spacing: 16) {
                    switch mode {
                    case .join: joinFields
                    case .admin: adminFields
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.geistCaption)
                            .foregroundStyle(Color.error)
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if isWorking {
                                ProgressView().tint(.white)
                            } else {
                                Text(mode == .join ? "Rejoindre" : (isCreatingAccount ? "Créer mon compte" : "Se connecter"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || !canSubmit)

                    if mode == .admin {
                        Button(isCreatingAccount ? "J'ai déjà un compte" : "Créer un compte administrateur") {
                            isCreatingAccount.toggle()
                            errorText = nil
                        }
                        .font(.geistSubheadline)
                    }
                }
            }
            .padding(.horizontal, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceBackground.ignoresSafeArea())
    }

    // MARK: - Fields

    @ViewBuilder
    private var joinFields: some View {
        labeled("Code") {
            TextField("ex. K7M2QX", text: $code)
                .font(.geistMonoHeadline)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focused, equals: .code)
                .submitLabel(.next)
                .onSubmit { focused = .name }
                .onChange(of: code) { _, new in
                    let cleaned = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    if cleaned != new { code = cleaned }
                    errorText = nil
                }
        }
        labeled("Votre nom") {
            TextField("Prénom Nom", text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .focused($focused, equals: .name)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }
        }
        Text("Votre nom apparaît sur les prospects que vous enregistrez.")
            .font(.geistCaption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var adminFields: some View {
        if isCreatingAccount {
            labeled("Votre nom") {
                TextField("Prénom Nom", text: $adminName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .focused($focused, equals: .adminName)
                    .submitLabel(.next)
                    .onSubmit { focused = .email }
            }
        }
        labeled("Email") {
            TextField("vous@exemple.com", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(.next)
                .onSubmit { focused = .password }
        }
        labeled(isCreatingAccount ? "Mot de passe (8 caractères min.)" : "Mot de passe") {
            SecureField("Mot de passe", text: $password)
                .textContentType(isCreatingAccount ? .newPassword : .password)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.geistHeadline)
            content().textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Submit

    private func submit() async {
        guard canSubmit, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorText = nil
        do {
            switch mode {
            case .join:
                try await AuthService.shared.join(code: trimmed(code), displayName: trimmed(name))
            case .admin where isCreatingAccount:
                try await AuthService.shared.signUp(email: trimmed(email).lowercased(), password: password, displayName: trimmed(adminName))
            case .admin:
                try await AuthService.shared.logIn(email: trimmed(email).lowercased(), password: password)
            }
            password = ""
            appState.phase = .loading   // LaunchView loads the account / event
        } catch let error as APIError {
            logger.error("Sign-in failed: \(error.code, privacy: .public)")
            switch (error.status, error.code) {
            case (401, "invalid_code"):        errorText = "Code invalide, ou \(mode == .join ? "événement terminé" : "expiré")."
            case (401, "invalid_credentials"): errorText = "Email ou mot de passe incorrect."
            case (409, "email_taken"):         errorText = "Un compte existe déjà avec cet email. Connectez-vous."
            default:                           errorText = error.localizedDescription
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    LoginView()
        .environment(AppState.preview())
}
