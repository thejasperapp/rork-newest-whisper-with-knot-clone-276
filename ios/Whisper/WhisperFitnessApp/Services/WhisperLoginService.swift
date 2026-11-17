import Foundation

/// Username lookup never exposes the account's email before password verification.
enum WhisperLoginService {
    nonisolated struct Tokens: Decodable {
        let access_token: String
        let refresh_token: String
        let user_id: String
    }

    static func usernameSession(identifier: String, password: String) async throws -> Tokens {
        guard let base = URL(string: Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL), base.scheme == "https" else {
            throw WhisperLoginError.unavailable
        }
        var request = URLRequest(url: base.appendingPathComponent("auth/password-login"))
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONEncoder().encode(Credentials(identifier: identifier, password: password))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WhisperLoginError.unavailable }
        if http.statusCode == 429 { throw WhisperLoginError.rateLimited }
        if http.statusCode == 401 { throw WhisperLoginError.invalidCredentials }
        guard http.statusCode == 200 else { throw WhisperLoginError.unavailable }
        return try JSONDecoder().decode(Tokens.self, from: data)
    }

    /// Obtain credentials without installing them in the shared SDK until the
    /// caller has checked the intended account and the still-current operation.
    static func passwordSession(email: String? = nil, phone: String? = nil, password: String) async throws -> Tokens {
        guard let base = URL(string: SupabaseService.supabaseURL), base.scheme == "https",
              !SupabaseService.supabaseAnonKey.isEmpty else { throw WhisperLoginError.unavailable }
        let url = base.appendingPathComponent("auth/v1/token").appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseService.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(PasswordCredentials(email: email, phone: phone, password: password))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WhisperLoginError.unavailable }
        if http.statusCode == 429 { throw WhisperLoginError.rateLimited }
        if http.statusCode == 400 || http.statusCode == 401 || http.statusCode == 422 { throw WhisperLoginError.invalidCredentials }
        guard http.statusCode == 200 else { throw WhisperLoginError.unavailable }
        let grant = try JSONDecoder().decode(PasswordGrant.self, from: data)
        guard phone == nil || grant.user.phone_confirmed_at != nil else { throw WhisperLoginError.invalidCredentials }
        return Tokens(access_token: grant.access_token, refresh_token: grant.refresh_token, user_id: grant.user.id)
    }

    private nonisolated struct PasswordCredentials: Encodable {
        let email: String?
        let phone: String?
        let password: String
    }

    private nonisolated struct PasswordGrant: Decodable {
        let access_token: String
        let refresh_token: String
        let user: Identity
        nonisolated struct Identity: Decodable {
            let id: String
            let phone_confirmed_at: String?
        }
    }

    private nonisolated struct Credentials: Encodable {
        let identifier: String
        let password: String
    }
}
