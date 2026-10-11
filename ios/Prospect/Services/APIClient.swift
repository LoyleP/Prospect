// Services/APIClient.swift
// Thin JSON-over-HTTPS client for the Prospect API (api/ in this repo, hosted on Vercel).
// Attaches the access token, refreshes it when needed, and retries once on 401.
import Foundation

struct APIError: Error, LocalizedError, Equatable {
    let status: Int
    let code: String
    let message: String

    var errorDescription: String? {
        switch status {
        case 0:   return "Erreur réseau — vérifiez votre connexion."
        case 401: return "Session expirée. Veuillez vous reconnecter."
        case 403: return "Votre rôle ne permet pas cette action."
        case 404: return "Élément introuvable."
        case 409: return code == "last_admin" ? "Une organisation doit garder au moins un administrateur." : "Ce nom est déjà utilisé."
        case 429: return "Trop de tentatives. Réessayez dans quelques minutes."
        default:  return message
        }
    }

    static let network = APIError(status: 0, code: "network", message: "Network error")
}

private struct ErrorBody: Decodable {
    let error: String
    let message: String
}

/// Marker for requests with no response body.
struct NoContent: Decodable {}

final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL = APIClient.configuredBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// `APIBaseURL` from Info.plist, set by the `API_BASE_URL` build setting in project.yml.
    static var configuredBaseURL: URL {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
            let url = URL(string: raw), url.scheme != nil
        else {
            fatalError("APIBaseURL manquant — définissez API_BASE_URL dans ios/project.yml")
        }
        return url
    }

    // MARK: - Requests

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send("GET", path, body: Optional<String>.none)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        try await send("POST", path, body: body)
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try await send("POST", path, body: Optional<String>.none)
    }

    func patch<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        try await send("PATCH", path, body: body)
    }

    func delete(_ path: String) async throws {
        let _: NoContent = try await send("DELETE", path, body: Optional<String>.none)
    }

    /// Authenticated request. Refreshes an expiring token first, and retries once if the server still says 401.
    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?) async throws -> T {
        try await AuthService.shared.refreshSessionIfNeeded()
        do {
            return try await perform(method, path, body: body, token: AuthService.shared.accessToken)
        } catch let error as APIError where error.status == 401 {
            try await AuthService.shared.forceRefresh()
            return try await perform(method, path, body: body, token: AuthService.shared.accessToken)
        }
    }

    /// Unauthenticated request (login endpoints).
    func sendPublic<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?) async throws -> T {
        try await perform(method, path, body: body, token: nil)
    }

    private func perform<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?, token: String?) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.network }

        guard (200..<300).contains(http.statusCode) else {
            let body = try? decoder.decode(ErrorBody.self, from: data)
            throw APIError(status: http.statusCode, code: body?.error ?? "http_\(http.statusCode)", message: body?.message ?? "Erreur serveur (\(http.statusCode))")
        }
        if T.self == NoContent.self || data.isEmpty {
            if let empty = NoContent() as? T { return empty }
        }
        return try decoder.decode(T.self, from: data)
    }
}
