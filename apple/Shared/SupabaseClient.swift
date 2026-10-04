import Foundation
import Security

/// Minimal hand-rolled Supabase client (PostgREST + GoTrue auth) over URLSession.
/// No external SPM dependency on purpose — keeps the first Xcode build simple.
/// Talks to the same project as index.html (see CLAUDE.md for the schema).
enum SupabaseConfig {
    static let url = URL(string: "https://pbttrknzevqmcqvcfcak.supabase.co")!
    // Public anon key — same one hardcoded in index.html's CONFIG.SUPABASE_ANON_KEY.
    // Safe to ship in the app bundle; RLS (not this key) gates all real access.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBidHRya256ZXZxbWNxdmNmY2FrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1ODEzODksImV4cCI6MjEwMjE1NzM4OX0.vQkG4sVXFRls2mMW0uM3cANmiopCzRzx0t78IAyRS-g"
}

enum SupabaseError: Error, LocalizedError {
    case notAuthenticated
    case http(Int, String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in."
        case .http(let code, let body): return "Server error \(code): \(body)"
        case .decoding(let err): return "Couldn't read server response: \(err.localizedDescription)"
        }
    }
}

struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

struct AuthUser: Codable {
    let id: String
    let email: String?
}

@MainActor
final class SupabaseClient: ObservableObject {
    static let shared = SupabaseClient()

    @Published private(set) var session: AuthSession?
    @Published private(set) var isLoading = true

    private let keychain = KeychainStore(service: "com.forgeit.app.auth")
    private var sessionFetchedAt: Date?
    private var refreshTask: Task<Void, Error>?

    private init() {
        Task { await restoreSession() }
    }

    var currentUserId: String? { session?.user.id }
    var isSignedIn: Bool { session != nil }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        let bodyData = try JSONEncoder().encode(["email": email, "password": password])
        let data = try await rawRequest(
            path: "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")],
            method: "POST", bodyData: bodyData, authorized: false
        )
        let newSession = try decode(AuthSession.self, from: data)
        session = newSession
        sessionFetchedAt = Date()
        try? keychain.save(newSession.refreshToken, forKey: "refresh_token")
    }

    func signUp(email: String, password: String) async throws {
        let bodyData = try JSONEncoder().encode(["email": email, "password": password])
        _ = try await rawRequest(path: "/auth/v1/signup", method: "POST", bodyData: bodyData, authorized: false)
    }

    func signOut() {
        session = nil
        try? keychain.delete(forKey: "refresh_token")
    }

    private func restoreSession() async {
        defer { isLoading = false }
        guard let refreshToken = try? keychain.read(forKey: "refresh_token"), !refreshToken.isEmpty else { return }
        do {
            try await refresh(using: refreshToken)
        } catch {
            try? keychain.delete(forKey: "refresh_token")
        }
    }

    private func refresh(using refreshToken: String) async throws {
        let bodyData = try JSONEncoder().encode(["refresh_token": refreshToken])
        let data = try await rawRequest(
            path: "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST", bodyData: bodyData, authorized: false
        )
        let newSession = try decode(AuthSession.self, from: data)
        session = newSession
        sessionFetchedAt = Date()
        try? keychain.save(newSession.refreshToken, forKey: "refresh_token")
    }

    /// Ensures a non-expired access token before every REST call. Supabase
    /// tokens default to a 1 hour lifetime; refresh a bit early. Several
    /// calls (e.g. NutritionService.loadDay's parallel `async let`s) can hit
    /// this at once — route them through a single in-flight refresh instead
    /// of each firing its own, which could race against Supabase's refresh
    /// token rotation and fail the second one.
    private func ensureFreshToken() async throws {
        guard let session else { throw SupabaseError.notAuthenticated }
        let age = Date().timeIntervalSince(sessionFetchedAt ?? .distantPast)
        guard age > Double(session.expiresIn - 60) else { return }

        if let existing = refreshTask {
            try await existing.value
            return
        }
        let task = Task { try await self.refresh(using: session.refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    // MARK: - PostgREST (table CRUD)

    func select<T: Decodable>(_ table: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        let data = try await rawRequest(path: "/rest/v1/\(table)", query: query, method: "GET", bodyData: nil)
        return try decode(type, from: data)
    }

    @discardableResult
    func insert<B: Encodable>(_ table: String, values: B, returning: Bool = false) async throws -> Data {
        let bodyData = try JSONEncoder().encode(values)
        let prefer = returning ? "return=representation" : "return=minimal"
        return try await rawRequest(path: "/rest/v1/\(table)", method: "POST", bodyData: bodyData, prefer: prefer)
    }

    @discardableResult
    func upsert<B: Encodable>(_ table: String, values: B, onConflict: String, returning: Bool = false) async throws -> Data {
        let bodyData = try JSONEncoder().encode(values)
        let prefer = "resolution=merge-duplicates," + (returning ? "return=representation" : "return=minimal")
        return try await rawRequest(
            path: "/rest/v1/\(table)", query: [URLQueryItem(name: "on_conflict", value: onConflict)],
            method: "POST", bodyData: bodyData, prefer: prefer
        )
    }

    @discardableResult
    func update<B: Encodable>(_ table: String, query: [URLQueryItem], values: B) async throws -> Data {
        let bodyData = try JSONEncoder().encode(values)
        return try await rawRequest(path: "/rest/v1/\(table)", query: query, method: "PATCH", bodyData: bodyData)
    }

    @discardableResult
    func delete(_ table: String, query: [URLQueryItem]) async throws -> Data {
        try await rawRequest(path: "/rest/v1/\(table)", query: query, method: "DELETE", bodyData: nil)
    }

    // MARK: - Low-level

    private func rawRequest(
        path: String, query: [URLQueryItem] = [], method: String,
        bodyData: Data?, authorized: Bool = true, prefer: String? = nil
    ) async throws -> Data {
        if authorized { try await ensureFreshToken() }

        var components = URLComponents(url: SupabaseConfig.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized, let token = session?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.http(0, "no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw SupabaseError.decoding(error) }
    }
}

/// Thin Keychain wrapper for the refresh token — avoids UserDefaults for anything auth-related.
struct KeychainStore {
    let service: String

    func save(_ value: String, forKey key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw SupabaseError.http(Int(status), "keychain save failed") }
    }

    func read(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
