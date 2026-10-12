// Services/AuthService.swift
// Sign-in (admin email + password, or an event code + name) and token lifecycle.
// Tokens live in the Keychain.
// Refresh tokens rotate on every use and the server treats a reused one as stolen,
// so concurrent refreshes are coalesced into a single request.
import Foundation
import KeychainAccess

struct AuthSession: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int
    /// "admin" or "participant".
    let kind: String

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt    = "expires_at"
        case kind
    }
}

private actor RefreshCoordinator {
    private var inFlight: Task<Void, Error>?

    /// Reads the current refresh token and stores the new pair *inside* the shared task,
    /// so a caller arriving later never sends a token that was just rotated out.
    func refresh() async throws {
        if let inFlight { return try await inFlight.value }
        let task = Task {
            guard let token = AuthService.shared.refreshToken else {
                throw APIError(status: 401, code: "unauthorized", message: "Not signed in")
            }
            let session: AuthSession = try await APIClient.shared.sendPublic(
                "POST", "/auth/refresh", body: ["refresh_token": token]
            )
            AuthService.shared.store(session)
        }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }
}

final class AuthService: @unchecked Sendable {
    static let shared = AuthService()

    /// Posted when the session can no longer be refreshed; AppState returns to the login screen.
    static let sessionExpired = Notification.Name("AuthService.sessionExpired")

    private let keychain = Keychain(service: "com.flow.prospect")
    private let coordinator = RefreshCoordinator()

    private init() {}

    // MARK: - Stored tokens

    var accessToken: String? { keychain["access_token"] }
    var refreshToken: String? { keychain["refresh_token"] }

    var tokenExpiry: Date? {
        guard let raw = keychain["token_expiry"], let seconds = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    var isSignedIn: Bool { DemoMode.active?.isSignedIn ?? (refreshToken != nil) }

    func store(_ session: AuthSession) {
        keychain["access_token"]  = session.accessToken
        keychain["refresh_token"] = session.refreshToken
        keychain["token_expiry"]  = String(session.expiresAt)
    }

    func clearSession() {
        for key in ["access_token", "refresh_token", "token_expiry"] {
            keychain[key] = nil
        }
    }

    /// True when the access token is valid for at least another minute.
    func isTokenValid(now: Date = Date()) -> Bool {
        guard accessToken != nil, let expiry = tokenExpiry else { return false }
        return expiry > now.addingTimeInterval(60)
    }

    // MARK: - Sign in

    /// Creates an admin account. No email verification by design.
    func signUp(email: String, password: String, displayName: String) async throws {
        if let demo = DemoMode.active { return try await demo.simulateSignIn(.admin(name: displayName, hasOrganization: false)) }
        store(try await APIClient.shared.sendPublic(
            "POST", "/auth/signup", body: ["email": email, "password": password, "display_name": displayName]
        ) as AuthSession)
    }

    func logIn(email: String, password: String) async throws {
        if let demo = DemoMode.active { return try await demo.simulateSignIn(.admin(name: "Camille Martin", hasOrganization: true)) }
        store(try await APIClient.shared.sendPublic(
            "POST", "/auth/login", body: ["email": email, "password": password]
        ) as AuthSession)
    }

    /// Joins one event as agent or conseiller with the code an admin handed out.
    func join(code: String, displayName: String) async throws {
        if let demo = DemoMode.active { return try await demo.simulateSignIn(.participant(code: code, name: displayName)) }
        store(try await APIClient.shared.sendPublic(
            "POST", "/auth/join", body: ["code": code, "display_name": displayName]
        ) as AuthSession)
    }

    func logout() async {
        if let demo = DemoMode.active { demo.signOut(); return }
        if let token = refreshToken {
            let _: NoContent? = try? await APIClient.shared.sendPublic("POST", "/auth/logout", body: ["refresh_token": token])
        }
        clearSession()
    }

    // MARK: - Refresh

    func refreshSessionIfNeeded() async throws {
        if isTokenValid() { return }
        try await forceRefresh()
    }

    func forceRefresh() async throws {
        do {
            try await coordinator.refresh()
        } catch let error as APIError where error.status == 401 {
            clearSession()
            NotificationCenter.default.post(name: Self.sessionExpired, object: nil)
            throw error
        }
    }
}
