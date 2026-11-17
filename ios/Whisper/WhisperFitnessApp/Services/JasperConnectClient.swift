import Foundation
import Security
import Supabase

// MARK: - Config

/// Jasper Connect — the one-click partner-app token drop-in from
/// `WHISPER_CONNECT.md` (thejasperapp.com). One tap mints a full-access
/// `jc_…` token via the `jasper_connect_authorize` RPC using the signed-in
/// user's OWN Supabase session (same project, same `auth.uid()`).
///
/// Division of labour (per the doc): in-app UI reads keep the direct
/// shared-Supabase `jasper_*` bridge; the Connect token is for the uniform
/// REST surface and for POSTING into Jasper (meals, workouts, charts to the
/// user's "Shared with you" inbox).
enum JasperConnectConfig {
    /// Same Supabase project Whisper already uses (matches SupabaseService).
    static let supabaseURL = URL(string: "https://uryyyegnbtlmyhqlgndy.supabase.co")!
    /// The public anon key (same constant Whisper already holds for its own client).
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyeXl5ZWduYnRsbXlocWxnbmR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyMzM3MDcsImV4cCI6MjA5MDgwOTcwN30.fBo6K9yNHmk1nTArspc5ByMsWEiI2SahCFk6Mdp7qUQ"
    /// Jasper Connect REST surface — the September 15, 2026 guide's service
    /// base (API revision 2026-09-12.1, compatibility patch 2026-09-14,
    /// contract 2026-09-11). Machine contract: /v1/catalog · /v1/openapi.json
    /// · /v1/experience. Older hosts still answer with earlier revisions, so
    /// every response's X-Jasper-API-Version is checked against `apiRevision`.
    static let apiBase = URL(string: "https://bpi3d9e8nzz0z8twjpfra-backend.rork.app")!
    static let apiRevision = "2026-09-12.1"
    static let compatibilityPatch = "2026-09-14"
    static let contractRevision = "2026-09-11"

    /// Routes whose POST/DELETE honor an Idempotency-Key: generic data
    /// resources, recipes and grocery changes. Connection mint/claim, token
    /// revocation, hooks, marketplace, link intents and the paused generation
    /// route do not, so the header is never sent there.
    nonisolated static func supportsIdempotency(path: String) -> Bool {
        let bare = path.split(separator: "?").first.map(String.init) ?? path
        let excluded = ["/v1/authorize", "/v1/requests", "/v1/tokens", "/v1/webhooks", "/v1/marketplace", "/v1/diet_plans/generate", "/v1/link-intents"]
        return !excluded.contains { bare == $0 || bare.hasPrefix($0 + "/") }
    }

    /// THE ONE INTEGRATION POINT — wired directly to Whisper's live Supabase
    /// session so the drop-in works with zero app-start ceremony. Overridable
    /// for tests.
    static var sessionJWT: @Sendable () async throws -> String = {
        let client = await MainActor.run { SupabaseService.shared.client }
        guard let session = try? await client.auth.session else {
            throw JasperConnectError.notSignedIn
        }
        return session.accessToken
    }
}

// MARK: - Models

nonisolated struct JasperConnection: Codable, Equatable {
    let tokenID: UUID          // jasper_connect_tokens.id — needed for revoke
    let tokenPrefix: String    // "jc_12345678" — safe to display
    let appName: String
    let scopes: [String]
    let kind: String           // "app" | "coach"
    let username: String?
    let displayName: String?
    /// §8.4: true = an account link / coach grant resolved a DIFFERENT owner
    /// account. nil = token metadata predates the field — fall back to the
    /// account-link service. Warning rule: username missing AND linked:false
    /// ⇒ unlinked sign-in (empty graph).
    let linked: Bool?
    let connectedAt: Date
    /// Jasper's `user.user_id` — the data owner this token resolves to,
    /// verified against the signed-in account before any record is shown.
    /// nil = metadata persisted before the September 15 guide.
    var userID: String? = nil

    var hasFullAccess: Bool { scopes.contains("all") }
    var scopeSummary: String {
        hasFullAccess ? "Full access" : "\(scopes.count) scopes"
    }
}

nonisolated enum JasperConnectState: Equatable {
    case notConnected
    case connecting
    case connected(JasperConnection)
    case error(String)
}

/// Read envelope: `{ ok, resource, count, data: [...] }` — only `data` is
/// modelled; declared at file scope because generic types can't nest inside
/// generic functions.
nonisolated private struct JasperRowsEnvelope<Row: Decodable>: Decodable {
    let data: [Row]
}

nonisolated struct JasperWriteReceipt: Decodable {
    let ok: Bool
    let resource: String?
    let id: UUID?
    let clientID: String?

    enum CodingKeys: String, CodingKey {
        case ok, resource, id
        case clientID = "client_id"
    }
}

/// One Connect token on YOUR Jasper account held by someone else (a coach) —
/// from `jasper_connect_connections()`, which resolves holder identity so
/// the coached client can SEE exactly who reads their graph (and revoke it
/// in Jasper → Settings → Connect).
nonisolated struct JasperCoachTokenInfo: Identifiable, Equatable {
    let id: String
    let appName: String
    let holderUsername: String?
    let holderDisplayName: String?
    let scopes: [String]
    let createdAt: Date?
    let lastUsedAt: Date?

    var canWrite: Bool { scopes.contains { $0 == "all" || $0.hasPrefix("write:") } }
}

/// One probed resource in the live "what Whisper sees" preview.
nonisolated struct JasperResourceSnapshot: Identifiable, Equatable {
    let resource: String   // e.g. "workouts"
    let title: String      // e.g. "Workouts"
    let symbol: String     // SF Symbol for the stat tile
    let count: Int         // rows inside the window
    let latest: Date?      // newest time-field value seen
    var id: String { resource }
}

nonisolated struct JasperLiveSnapshot: Equatable {
    let fetchedAt: Date
    let windowDays: Int
    let resources: [JasperResourceSnapshot]
    /// Titles of probes that errored this pass (partial reads stay honest).
    let failedResources: [String]
    var totalRows: Int { resources.reduce(0) { $0 + $1.count } }

    /// Headline resources + their §8-appendix time fields.
    static let probes: [(resource: String, title: String, symbol: String, timeField: String)] = [
        ("workouts", "Workouts", "figure.strengthtraining.traditional", "performed_at"),
        ("meals", "Meals", "fork.knife", "logged_at"),
        ("sleep", "Sleep", "moon.zzz.fill", "started_at"),
        ("weight", "Weight", "scalemass.fill", "measured_at"),
        ("steps", "Steps", "shoeprints.fill", "recorded_on"),
        ("personal_records", "PRs", "trophy.fill", "achieved_at"),
    ]
}

/// Lenient date parsing for §8 time fields — full ISO 8601 (with or without
/// fractional seconds) or bare `yyyy-MM-dd` day stamps like `recorded_on`.
/// Internal: `JasperCoachConnect` parses the same §8 shapes.
nonisolated func jasperConnectDate(_ value: Any?) -> Date? {
    guard let raw = value as? String, !raw.isEmpty else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: raw) { return date }
    if let date = ISO8601DateFormatter().date(from: raw) { return date }
    let day = DateFormatter()
    day.locale = Locale(identifier: "en_US_POSIX")
    day.timeZone = TimeZone(identifier: "UTC")
    day.dateFormat = "yyyy-MM-dd"
    return day.date(from: raw)
}

nonisolated enum JasperConnectError: LocalizedError {
    case notWired
    case notSignedIn
    case notConnected
    case revoked
    case server(String)
    /// 429 with Retry-After — back off; never retry a mutation on its own.
    case rateLimited(retryAfter: Int?, requestID: String?)

    var errorDescription: String? {
        switch self {
        case .notWired: return "Jasper Connect isn't wired up."
        case .notSignedIn: return "Sign in to Whisper first."
        case .notConnected: return "Jasper isn't connected yet."
        case .revoked: return "This connection was revoked. Reconnect to continue."
        case .server(let message): return message
        case .rateLimited(let retryAfter, let requestID):
            let wait = retryAfter.map { " Try again in \($0)s." } ?? " Try again in a minute."
            let reference = requestID.map { " · request \($0.prefix(8))" } ?? ""
            return "rate_limited — Jasper is busy right now." + wait + reference
        }
    }
}

/// One sanitized API failure (guide §08): the stable `error` code, the
/// X-Request-Id to quote in reports, and the few structured hints the
/// contract defines (`need` on missing_scope, `hint`, Retry-After). Response
/// bodies and credentials never travel into messages or logs. Messages keep
/// the code as their first word so the existing UI mappers still match.
nonisolated struct JasperConnectFailure: Sendable, Equatable {
    let status: Int
    let code: String
    let requestID: String?
    let need: String?
    let hint: String?
    let retryAfter: Int?

    init(status: Int, response: HTTPURLResponse?, data: Data) {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let details = body["error_details"] as? [String: Any]
        self.status = status
        self.code = (details?["code"] as? String) ?? (body["error"] as? String) ?? "http_\(status)"
        self.requestID = response?.value(forHTTPHeaderField: "X-Request-Id") ?? (body["request_id"] as? String)
        self.need = body["need"] as? String
        self.hint = body["hint"] as? String
        self.retryAfter = response?.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Any 401 (invalid_token, coach_grant_revoked) or 409 connection_changed:
    /// the credential is dead — wipe it and never retry under it.
    var isRevocation: Bool {
        status == 401 || code == "invalid_token" || code == "coach_grant_revoked" || code == "connection_changed"
    }

    /// Short request-id tail for messages — enough to find the log line.
    var reference: String { requestID.map { " · request \($0.prefix(8))" } ?? "" }

    var message: String {
        switch code {
        case "missing_scope":
            return "missing_scope — this wasn't shared" + (need.map { " (need \($0))" } ?? "") + "." + reference
        case "coach_grant_read_only":
            return "coach_grant_read_only — this coaching grant is view-only; reads keep working." + reference
        case "native_review_required":
            return JasperConnectClient.nativeReviewMessage
        case "idempotency_conflict":
            return "idempotency_conflict — the same change was already sent with a different payload; start a fresh attempt." + reference
        case "idempotency_in_progress":
            return "idempotency_in_progress — that change is still being applied; wait before retrying." + reference
        case "idempotency_expired":
            return "idempotency_expired — this retry is older than 24 hours; start a fresh attempt." + reference
        case "unknown_resource":
            return "unknown_resource — this Jasper deployment doesn't offer that resource." + reference
        case "webhook_egress_unavailable":
            return "webhook_egress_unavailable — Jasper has paused webhook push; Whisper reads the change feed instead." + reference
        default:
            if let hint { return "\(code) — \(hint)" + reference }
            return "\(code) (\(status))" + reference
        }
    }
}

// MARK: - Keychain (raw token only — metadata lives in UserDefaults)

private enum JasperConnectKeychain {
    private static let service = "jasper.connect"
    private static var account: String { "jc_token_v2_" + AccountStorage.currentUserID.lowercased() }

    static func save(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// False when the Keychain refused to delete a live row — the caller
    /// still honors the revocation and reports the failed cleanup.
    @discardableResult
    static func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - Client

@MainActor
@Observable
final class JasperConnectClient {
    static let shared = JasperConnectClient()

    private(set) var state: JasperConnectState = .notConnected
    /// Last successful live snapshot — shared by the settings card, the
    /// celebration screen, and the assistant briefing (5-minute freshness).
    private(set) var cachedSnapshot: JasperLiveSnapshot?
    /// Human-readable reason the last snapshot (or part of it) failed.
    private(set) var lastLiveError: String?
    @ObservationIgnored private var inFlightSnapshot: Task<JasperLiveSnapshot?, Never>?

    private var metaKey: String { "jasper_connect_meta_v2_" + AccountStorage.currentUserID.lowercased() }
    private var connectionGeneration: UUID = UUID()
    private var stateOwner: String = AccountStorage.currentUserID.lowercased()
    private(set) var isDisconnecting: Bool = false
    private(set) var disconnectError: String?
    /// Contract check (guide §01 "Version check"): the revision the last
    /// response declared, the patch /v1/experience reports, and a note when a
    /// host answers with something other than what this build was written for.
    private(set) var apiVersion: String?
    private(set) var compatibilityPatch: String?
    private(set) var contractNote: String?
    /// The last failed call, sanitized — status, code and X-Request-Id only.
    private(set) var lastFailure: JasperConnectFailure?
    /// True when a 401 was honored but the Keychain refused to delete the dead
    /// token (guide: report credentialCleanupFailed instead of hiding it).
    private(set) var credentialCleanupFailed: Bool = false
    nonisolated static let nativeReviewMessage = "Connected meal generation is paused. Create and review your plan in Jasper’s Nutrition screen, then refresh your saved plans here. Nothing was generated or saved."
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {
        restore()
    }

    var connection: JasperConnection? {
        guard stateOwner == AccountStorage.currentUserID.lowercased() else { return nil }
        if case .connected(let info) = state { return info }
        return nil
    }

    // MARK: Lifecycle

    /// Rehydrate from Keychain + UserDefaults, then verify in the background
    /// so a remotely-revoked token flips the UI back to "Connect Jasper".
    func restore() {
        stateOwner = AccountStorage.currentUserID.lowercased()
        guard UUID(uuidString: stateOwner) != nil,
              JasperConnectKeychain.load() != nil,
              let data = UserDefaults.standard.data(forKey: metaKey),
              let meta = try? decoder.decode(JasperConnection.self, from: data) else {
            state = .notConnected
            return
        }
        state = .connected(meta)
    }

    /// Validation runs only after the app and SDK agree on the restored owner.
    /// Loading durable consent must never mint a replacement token.
    func resumeAfterSignIn() async {
        guard let context = try? await JasperAccountSession.current() else { return }
        if stateOwner != context.ownerID { accountDidChange() }
        guard connection != nil else { return }
        async let contract: Void = checkContract()
        await validate()
        _ = await contract
    }

    /// GET /v1/experience (no auth): confirms the host speaks the revision and
    /// compatibility patch this build was written against. Never blocks reads
    /// — an older host is reported in `contractNote`, not refused.
    func checkContract() async {
        guard var components = URLComponents(url: JasperConnectConfig.apiBase, resolvingAgainstBaseURL: false) else { return }
        components.path = "/v1/experience"
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
        noteContract(http)
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        compatibilityPatch = body?["compatibility_patch"] as? String
        refreshContractNote()
    }

    private func noteContract(_ response: HTTPURLResponse) {
        if let version = response.value(forHTTPHeaderField: "X-Jasper-API-Version"), version != apiVersion {
            apiVersion = version
            refreshContractNote()
        }
    }

    private func refreshContractNote() {
        var notes: [String] = []
        if let apiVersion, apiVersion != JasperConnectConfig.apiRevision {
            notes.append("API \(apiVersion) (this build expects \(JasperConnectConfig.apiRevision))")
        }
        if let compatibilityPatch, compatibilityPatch < JasperConnectConfig.compatibilityPatch {
            notes.append("compatibility patch \(compatibilityPatch) (this build expects \(JasperConnectConfig.compatibilityPatch))")
        }
        contractNote = notes.isEmpty ? nil : "This Jasper host answers with " + notes.joined(separator: " and ") + " — fixes from the September 14 patch may be missing."
    }

    /// Invoked only after the permission picker is explicitly approved.
    func connect(scopes: [String]) async {
        guard state != .connecting, !isDisconnecting, !scopes.isEmpty,
              scopes.allSatisfy({ JasperPermissionChoice.options.map(\.id).contains($0) }) else { return }
        connectionGeneration = UUID()
        let epoch = connectionGeneration
        let account = AccountStorage.generation
        cachedSnapshot = nil
        inFlightSnapshot?.cancel()
        inFlightSnapshot = nil
        state = .connecting
        do {
            let context = try await JasperAccountSession.current()
            guard epoch == connectionGeneration, account == AccountStorage.generation else { return }
            let body = try await authorize(appName: "Whisper", scopes: scopes, context: context)
            try context.check()
            guard epoch == connectionGeneration else { return }

            guard body["ok"] as? Bool == true,
                  let raw = body["token"] as? String,
                  let idString = body["id"] as? String,
                  let tokenID = UUID(uuidString: idString), raw.hasPrefix("jc_"),
                  let granted = body["scopes"] as? [String], granted.allSatisfy({ scopes.contains($0) }) else {
                let message = (body["error"] as? String) ?? "Jasper didn't return a token."
                let hint = body["hint"] as? String
                state = .error([message, hint].compactMap { $0 }.joined(separator: " "))
                return
            }

            let user = body["user"] as? [String: Any]
            let userID = (user?["user_id"] as? String)?.lowercased()
            // Guide §09: verify user.user_id before showing any record. An own
            // connection must resolve to this signed-in account unless Jasper
            // says an account link resolved a different owner (linked:true).
            if let userID, userID != context.ownerID, user?["linked"] as? Bool != true {
                state = .error("Jasper answered for a different account than the one signed in here. Check your Jasper account link, then try again.")
                return
            }
            let info = JasperConnection(
                tokenID: tokenID,
                tokenPrefix: (body["token_prefix"] as? String) ?? String(raw.prefix(11)),
                appName: (body["app_name"] as? String) ?? "Whisper",
                scopes: granted,
                kind: (body["kind"] as? String) ?? "app",
                username: user?["username"] as? String,
                displayName: user?["display_name"] as? String,
                linked: user?["linked"] as? Bool,
                connectedAt: Date(),
                userID: userID
            )
            guard JasperConnectKeychain.save(raw) else {
                state = .error("Your iPhone couldn't securely save the Jasper connection. Unlock it and try again.")
                return
            }
            persist(info)
            cachedSnapshot = nil        // fresh token — never show stale numbers
            lastLiveError = nil
            stateOwner = context.ownerID
            state = .connected(info)
        } catch {
            guard epoch == connectionGeneration, account == AccountStorage.generation, !Task.isCancelled else { return }
            state = .error(friendly(error))
        }
    }

    /// Revoke server-side (works even if the token already died), then wipe.
    @discardableResult
    func disconnect() async -> Bool {
        guard !isDisconnecting, state != .connecting else { return false }
        guard let info = connection else { return false }
        let account = AccountStorage.generation
        connectionGeneration = UUID()
        let epoch = connectionGeneration
        isDisconnecting = true
        disconnectError = nil
        cachedSnapshot = nil
        inFlightSnapshot?.cancel()
        inFlightSnapshot = nil
        defer { if epoch == connectionGeneration { isDisconnecting = false } }
        do {
            let context = try await JasperAccountSession.current()
            let confirmed = try await revokeToken(id: info.tokenID.uuidString, context: context)
            try context.check()
            guard epoch == connectionGeneration, account == AccountStorage.generation else { return false }
            guard confirmed else { throw JasperConnectError.server("Couldn't confirm revocation. Retry or revoke Whisper in Jasper → Settings → Jasper Connect.") }
            wipe()
            return true
        } catch {
            guard epoch == connectionGeneration, account == AccountStorage.generation else { return false }
            disconnectError = "Couldn't confirm disconnection. Try again, or revoke Whisper in Jasper → Settings → Jasper Connect."
            return false
        }
    }

    /// GET /v1/me — detects remote revoke/expiry and clears local state on 401.
    /// Also folds the freshest identity (username / display name / linked)
    /// back into the cached metadata so the settings indicator can't go stale.
    /// Returns true when the connection is verified healthy.
    @discardableResult
    func validate() async -> Bool {
        guard let current = connection, !isDisconnecting else { return false }
        let epoch = connectionGeneration
        do {
            let data = try await dataRequest(path: "/v1/me", method: "GET", payload: nil)
            guard epoch == connectionGeneration, connection?.tokenID == current.tokenID else { return false }
            refreshIdentity(from: data, current: current)
            return true
        } catch JasperConnectError.revoked {
            if epoch == connectionGeneration { wipe() }
            return false
        } catch {
            // Network blips keep the cached connected state — never punish offline.
            return false
        }
    }

    /// Lenient about response shape: reads `user.{username,display_name,linked}`
    /// (or the same keys at the top level) and ignores anything unknown.
    private func refreshIdentity(from data: Data, current: JasperConnection) {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let user = (body["user"] as? [String: Any]) ?? body
        let updated = JasperConnection(
            tokenID: current.tokenID,
            tokenPrefix: current.tokenPrefix,
            appName: current.appName,
            scopes: (body["scopes"] as? [String]) ?? current.scopes,
            kind: current.kind,
            username: (user["username"] as? String) ?? current.username,
            displayName: (user["display_name"] as? String) ?? current.displayName,
            linked: (user["linked"] as? Bool) ?? current.linked,
            connectedAt: current.connectedAt,
            userID: ((user["user_id"] as? String)?.lowercased()) ?? current.userID
        )
        if updated != current {
            persist(updated)
            state = .connected(updated)
        }
    }

    // MARK: Reads — GET /v1/<resource> → { ok, resource, count, data: [...] }

    /// Decoded rows. Model each resource with a small Decodable struct.
    func rows<T: Decodable>(_ resource: String, of type: T.Type,
                            since: Date? = nil, limit: Int? = nil,
                            cursor: Int? = nil) async throws -> [T] {
        let data = try await read(resource, since: since, limit: limit, cursor: cursor)
        return try decoder.decode(JasperRowsEnvelope<T>.self, from: data).data
    }

    /// Raw envelope bytes when you'd rather JSONSerialization your way through.
    func read(_ resource: String, since: Date? = nil, limit: Int? = nil,
              cursor: Int? = nil) async throws -> Data {
        var query: [URLQueryItem] = []
        if let since { query.append(URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: since))) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: String(cursor))) }
        let data = try await dataRequest(path: "/v1/\(resource)", query: query, method: "GET", payload: nil)
        // Native render specs ride along with the data — capture them so
        // Whisper draws Jasper data exactly like Jasper does.
        JasperLookStore.shared.ingest(resource: resource, envelope: data)
        return data
    }

    /// The user's OWN one-call dashboard — the same `GET /v1/dashboard`
    /// envelope coach tokens read, through the user's own token. Powers
    /// Jasper Intelligence's native in-chat data cards (readiness, sleep,
    /// blood) so chat quotes the exact payload every other surface renders.
    func ownDashboard(period: String? = nil) async throws -> Data {
        var query: [URLQueryItem] = []
        if let period { query.append(URLQueryItem(name: "period", value: period)) }
        return try await dataRequest(path: "/v1/dashboard", query: query, method: "GET", payload: nil)
    }

    /// GET /v1/workspace — the opt-in grouped, scope-gated cloud snapshot
    /// (training, nutrition, insights, goals). Locked sections arrive as
    /// locks, never zeros; a 409 connection_changed mid-assembly surfaces as
    /// `.revoked` so callers discard and refresh.
    func workspace() async throws -> Data {
        try await dataRequest(path: "/v1/workspace", method: "GET", payload: nil)
    }

    /// GET /v1/events/page — the change-feed journal (guide §06). Send the
    /// returned `next_cursor` AND `context` back together on the next call.
    /// `overrideToken` reads a coached client's journal through the coach-held token.
    func eventsPage(cursor: String, context: String?, limit: Int = 200,
                    overrideToken: String? = nil) async throws -> Data {
        var query = [URLQueryItem(name: "cursor", value: cursor), URLQueryItem(name: "limit", value: String(min(200, max(1, limit))))]
        if let context { query.append(URLQueryItem(name: "context", value: context)) }
        return try await dataRequest(path: "/v1/events/page", query: query, method: "GET",
                                     payload: nil, overrideToken: overrideToken)
    }

    /// GET /v1/history/{resource} — UUID-keyset pages for reconciliation,
    /// or one exact row by `id`. Continue with the returned cursor and context.
    func history(_ resource: String, cursor: String? = nil, context: String? = nil,
                 id: String? = nil, limit: Int = 100, overrideToken: String? = nil) async throws -> Data {
        var query = [URLQueryItem(name: "limit", value: String(min(200, max(1, limit))))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let context { query.append(URLQueryItem(name: "context", value: context)) }
        if let id { query.append(URLQueryItem(name: "id", value: id)) }
        return try await dataRequest(path: "/v1/history/\(resource)", query: query, method: "GET",
                                     payload: nil, overrideToken: overrideToken)
    }

    // MARK: Live snapshot — "what Whisper sees" (§8 appendix resources)

    /// Counts + freshest timestamp for the headline resources over a trailing
    /// window, cached for 5 minutes so the settings card, the celebration
    /// screen, and the assistant briefing all share one read. `force` bypasses
    /// the cache. Returns nil only when nothing could be read at all.
    func liveSnapshot(days: Int = 30, force: Bool = false) async -> JasperLiveSnapshot? {
        guard connection != nil, !isDisconnecting else { return nil }
        let epoch = connectionGeneration
        Task { await JasperLookStore.shared.refreshIfStale() }
        if !force, let cached = cachedSnapshot,
           Date().timeIntervalSince(cached.fetchedAt) < 300 {
            return cached
        }
        if let running = inFlightSnapshot { return await running.value }
        let task = Task<JasperLiveSnapshot?, Never> { await self.fetchSnapshot(days: days) }
        inFlightSnapshot = task
        let result = await task.value
        guard epoch == connectionGeneration else { return nil }
        inFlightSnapshot = nil
        return result
    }

    /// The actual network pass. Sequential per the doc's politeness contract
    /// (sustained ≤1 req/s; page cap 200). One resource failing is skipped —
    /// only a total wipe-out (or a revoke) returns nil.
    private func fetchSnapshot(days: Int) async -> JasperLiveSnapshot? {
        let epoch = connectionGeneration
        let account = AccountStorage.generation
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        var out: [JasperResourceSnapshot] = []
        var failures: [String] = []
        var lastError: String?
        for probe in JasperLiveSnapshot.probes {
            guard connection != nil, epoch == connectionGeneration, account == AccountStorage.generation, !Task.isCancelled else { return nil }
            do {
                let data = try await read(probe.resource, since: since, limit: 200)
                let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let rows = (body?["data"] as? [[String: Any]]) ?? []
                let latest = rows.compactMap { jasperConnectDate($0[probe.timeField]) }.max()
                out.append(JasperResourceSnapshot(resource: probe.resource, title: probe.title,
                                                  symbol: probe.symbol, count: rows.count,
                                                  latest: latest))
            } catch JasperConnectError.revoked {
                if epoch == connectionGeneration { wipe() }
                return nil
            } catch {
                let message = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
                failures.append(probe.title)
                lastError = message
                guard epoch == connectionGeneration, account == AccountStorage.generation, !Task.isCancelled else { return nil }
            }
        }
        guard epoch == connectionGeneration, account == AccountStorage.generation, !Task.isCancelled else { return nil }
        guard !out.isEmpty else {
            lastLiveError = lastError
            return nil
        }
        let snap = JasperLiveSnapshot(fetchedAt: Date(), windowDays: days,
                                      resources: out, failedResources: failures)
        cachedSnapshot = snap
        lastLiveError = failures.isEmpty ? nil : lastError
        // Guide §06: reconcile the change feed on the same rail as the read,
        // when the user shared it (read:events); hints only, never a retry.
        if let scopes = connection?.scopes, scopes.contains("read:events") || scopes.contains("all") {
            let owner = stateOwner
            Task { await JasperEventPush.shared.reconcile(uid: owner, via: .own) }
        }
        return snap
    }

    // MARK: Coach visibility (client side)

    /// Tokens on THIS user's Jasper account held by coaches ("Whisper Coach ·
    /// …") — Jasper's `jasper_connect_connections()` resolves holder identity
    /// so the client can see exactly who reads their graph. Forgiving parse;
    /// empty on any failure (visibility must never break settings).
    func coachConnections() async -> [JasperCoachTokenInfo] {
        guard let jwt = try? await JasperConnectConfig.sessionJWT(),
              let rows = try? await rpcRows("jasper_connect_connections", params: [:], jwt: jwt) else {
            return []
        }
        return rows.compactMap { row in
            let appName = (row["app_name"] as? String) ?? ""
            if let status = row["status"] as? String, status.lowercased() != "active" { return nil }
            let holderIsSelf = (row["holder_is_self"] as? Bool) ?? (row["is_own"] as? Bool)
            let isCoachHeld = appName.lowercased().hasPrefix("whisper coach") || holderIsSelf == false
            guard isCoachHeld else { return nil }
            let scopes = (row["scopes"] as? [String])
                ?? (row["scopes"] as? String).map { [$0] }
                ?? []
            let id = (row["id"] as? String)
                ?? (row["token_prefix"] as? String)
                ?? appName
            return JasperCoachTokenInfo(
                id: id,
                appName: appName,
                holderUsername: (row["holder_username"] as? String)
                    ?? (row["coach_username"] as? String)
                    ?? (row["holder"] as? String),
                holderDisplayName: (row["holder_display_name"] as? String)
                    ?? (row["display_name"] as? String),
                scopes: scopes,
                createdAt: jasperConnectDate(row["created_at"]),
                lastUsedAt: jasperConnectDate(row["last_used_at"] ?? row["last_used"]))
        }
    }

    // MARK: Writes — POST /v1/<resource> → { ok, resource, id, client_id }

    /// One deliberate write. `client_id` in the payload is record identity
    /// (upsert), not retry protection — the Idempotency-Key is. Every call
    /// mints a fresh key; a caller that lets the user retry the SAME change
    /// passes the key it used the first time. Nothing here retries on its own.
    @discardableResult
    func post(_ resource: String, _ payload: [String: Any],
              idempotencyKey: String = UUID().uuidString) async throws -> JasperWriteReceipt {
        let data = try await dataRequest(path: "/v1/\(resource)", method: "POST", payload: payload, idempotencyKey: idempotencyKey)
        return try decoder.decode(JasperWriteReceipt.self, from: data)
    }

    /// DELETE /v1/<resource>?id=<row id or client_id> under the same scope as
    /// POST; Jasper emits a <thing>.deleted event. Charts: only Whisper's own
    /// posts. Returns the contract's `deleted` count (0 or 1).
    @discardableResult
    func delete(_ resource: String, id: String,
                idempotencyKey: String = UUID().uuidString) async throws -> Int {
        let data = try await dataRequest(path: "/v1/\(resource)", query: [URLQueryItem(name: "id", value: id)],
                                         method: "DELETE", payload: nil, idempotencyKey: idempotencyKey)
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (body?["deleted"] as? Int) ?? 0
    }

    /// Post a Jasper-format chart / bio-age card into the user's Shared inbox
    /// (§5, authoritative): `title` required; `chart` required unless
    /// kind == "card" (text-only); "bioage" is a display tag, never an engine
    /// input. Build the chart object with `chartObject(...)` — the renderer
    /// draws the last 24 numbers from `values` (or `points[].y`, which MUST be
    /// numeric — a "value" key renders an empty chart).
    @discardableResult
    func postChart(title: String, kind: String = "chart",
                   chart: [String: Any]? = nil, note: String? = nil,
                   idempotencyKey: String = UUID().uuidString) async throws -> JasperWriteReceipt {
        var payload: [String: Any] = ["title": title, "kind": kind]
        if let chart { payload["chart"] = chart }
        if let note { payload["note"] = note }
        return try await post("charts", payload, idempotencyKey: idempotencyKey)
    }

    /// Spec-compliant chart object (§5). `values` is the renderer's preferred
    /// series; `labels` pairs with it; `type` hints "line" or "bar".
    nonisolated static func chartObject(type: String = "line", unit: String? = nil,
                                        values: [Double], labels: [String]? = nil) -> [String: Any] {
        var chart: [String: Any] = ["type": type, "values": values]
        if let unit { chart["unit"] = unit }
        if let labels { chart["labels"] = labels }
        return chart
    }

    // MARK: Assistant briefing

    /// Everything the in-app Jasper assistant needs to know about this
    /// connection — folded into the Atlas live-state block every turn so it
    /// can answer "what can Whisper see from Jasper?" truthfully.
    var assistantBriefing: String {
        guard let info = connection else {
            return "JASPER CONNECT (partner fitness app API): NOT connected. The user can connect in Settings → Sync with Jasper (choose and approve permissions). Until then live Jasper API reads/writes are unavailable — suggest connecting when fitness data comes up. Jasper's public plan MARKETPLACE still works without a connection (browse/preview are public) — attach a marketplace action when plan templates come up; importing needs a connection (own Jasper) or an accepted coaching client."
        }
        var lines: [String] = []
        var head = "JASPER CONNECT (partner fitness app API): ACTIVE — \(info.scopeSummary.lowercased()) token"
        if let username = info.username { head += ", connected as @\(username)" }
        head += ". Granted scopes: \(info.scopes.joined(separator: ", ")). Revocable in Jasper or Whisper settings; never assume broader permissions."
        lines.append(head)
        if let contractNote { lines.append("CONTRACT CHECK: " + contractNote) }
        if credentialCleanupFailed { lines.append("CREDENTIAL CLEANUP FAILED: a revoked token could not be removed from the Keychain — tell the user to sign out and back in.") }
        if let snap = cachedSnapshot {
            let counts = snap.resources.map { "\($0.title) \($0.count)" }.joined(separator: ", ")
            lines.append("Live counts (last \(snap.windowDays) days): \(counts).")
        }
        lines.append("AUTO-PULL: when the user mentions diet, meals, macros, or groceries, Whisper pulls diet_plans live off this token for that turn and hands you a JASPER DIET PLAN block — answer from it and attach a dietplan or groceries action (they open the live plan / checklist in-app).")
        lines.append("COACH AUTO-PULL: when a coach names an accepted client, you also receive a CLIENT LIVE DASHBOARD block (one-call GET /v1/dashboard through the coach token) — quote it for status questions and attach a clientdashboard action (a live dashboard card that opens right in chat).")
        lines.append("MARKETPLACE IS LIVE IN WHISPER: browse/publish/import all have real UI — Coach Studio → Plan marketplace, a Marketplace button on every client dashboard (imports preselect that client), Coach tools → Program → 'Also publish to the marketplace', and a marketplace chat action. Never say the marketplace UI is coming — it shipped.")
        lines.append("PROGRAMS STUDIO IS THE API (route coach_programs): the Programs screen renders GET /v1/programs AND GET /v1/diet_plans live off the coach's own token — Training and Diet tabs, one-tap 'Publish to marketplace' on every live row, Whisper-only drafts kept separately for DM selling, and a paused-generation notice in the Diet tab directing users to Jasper's reviewed native Nutrition flow. Both plan builders open FULL SCREEN, as do Coach tools. Meeting-style quick-analysis docks (the mascot peeking from behind the pill) sit on the inbox and every client profile — they run an automatic in-place Jasper analysis.")
        lines.append("NATIVE PLAN LOOKS (WHISPER_PLANS spec, published at thejasperapp.com/WHISPER_PLANS.md): every program and diet plan in Whisper wears Jasper's ember GLOW BOX — warm cream (light) / charcoal (dark) opaque card, warm gradient hairline, layered ember aura — with glow-icon headers, WORKOUT PLAN / DIET PLAN kickers, ember-gradient day dots, macro tiles in the canonical colors (kcal ember, protein teal, carbs amber, fat blue), reps strings rendered verbatim, teal grocery check circles wired to the shared POST /v1/grocery_list state. Connected meal generation is paused, with no simulated waiting progress. Studio rows open a day-by-day program detail sheet or the full diet plan sheet. The mood selector is the full-screen ghost carousel; the header blob button opens it.")
        lines.append("NATIVE DATA CARDS IN CHAT: you can render LIVE Jasper data as native in-chat cards via the ```jasper fence — bioage (vitality blob), readiness (recovery ring + 14-day trend; covers stress/strain questions), sleep (stage hypnogram), water (the animated tap-to-log cup), blood (PhenoAge + nine markers, honoring the read:blood lock). They pull the one-call dashboard or the live resource at render time — own token for the user, coach token when a client is named — so the card is always current and always honest about what isn't shared.")
        lines.append("NUTRITION IS TWO-WAY SHARED STATE (Aug 17): recipes are first-class — when you write a recipe, attach a recipe action (it opens a save-ready editor; one tap lands it inside Jasper under Nutrition → Recipes instantly, and the user's own Jasper recipes read back in Whisper's Recipes sheet on the Jasper card). The grocery checklist is the SAME rows as Jasper's in-app list — a check in Whisper is checked in Jasper and vice versa, live. Coaches cannot generate connected meal plans while native nutrition review is required. Hydration renders as Jasper's animated water cup everywhere, with tap-to-log on the user's own tracker (Jasper card → Water).")
        lines.append(Self.apiSurfaceBriefing)
        return lines.joined(separator: "\n")
    }

    /// The full Connect resource surface, from GET /v1/catalog — what Whisper
    /// can read from and post into the partner Jasper fitness app.
    nonisolated static let apiSurfaceBriefing = """
    SEPTEMBER 15, 2026 GUIDE — service base https://bpi3d9e8nzz0z8twjpfra-backend.rork.app/v1 (API revision 2026-09-12.1, compatibility patch 2026-09-14, contract 2026-09-11; Whisper checks every X-Jasper-API-Version and /v1/experience.compatibility_patch and reports an older host instead of trusting it). Only actual granted scopes authorize reads/writes. Missing, empty, locked and unavailable are distinct, not zero activity. Any 401 (invalid_token, coach_grant_revoked) or 409 connection_changed discards private caches and credentials; reconnect only after explicit approval, never auto-mint. Every error carries a stable code and an X-Request-Id — quote the request id, never response bodies or tokens. Writes happen only after an explicit user action and carry one Idempotency-Key per deliberate attempt (409 idempotency_conflict / _in_progress / _expired are surfaced, never retried automatically). Webhook push is paused server-side (webhook_egress_unavailable): change hints come from GET /v1/events/page (next_cursor + context travel together) and periodic /v1/history/{resource} scans; hints are not complete mutation coverage. 429 carries Retry-After (240 requests/minute per IP and per data owner) — back off. Never publish, send or change records just because they are readable. Private Files and original health reports are excluded. GET /v1/workspace and /v1/experience are partner API capabilities; a grouped workspace screen is not yet implemented in Whisper.
    HEALTH HONESTY: biological age is exploratory, not clinical; unversioned readiness must not be relabeled recovery-v2; nightly sleep totals cannot reconstruct a timed hypnogram. Planned meal estimates, saved targets and logged intake are separate. Macro review does not certify allergens or nutrient adequacy.
    READABLE from Jasper: profile (identity + lifetime rollups), streaks (per-habit current/longest), achievements, workouts (duration, sets/reps, volume kg, heart rate, kcal, per-exercise snapshot), personal_records (1RM/volume/rep PRs), programs (training programs), meals (full macros + food breakdown), water (ml — reads carry Jasper's water_cup render spec: the animated tapered glass with the sine-wave fill that Whisper draws natively), recipes (the saved recipe library — ingredients as loggable foods, steps, per-serving macros computed server-side; ONE shared object with Jasper's Nutrition → Recipes), diet_plans (macro targets + the full plan payload incl. groceryList — the canonical categorized grocery checklist Jasper renders in-app; Whisper shows it verbatim on the Jasper card and coach dashboards, never re-derived from ingredients), preferences (the user's preference object — nutrition goals etc.), sleep (sessions + stages), readiness, heart_rate, steps, energy, body (measurements), weight (log), progress_photos (metadata only — photo bytes stay in Jasper's private storage), bioage (exploratory biological-age history — read-only by design), blood_panels (biomarkers), goals + goal_entries, shared_charts (the shared inbox), events (change feed). Reads of bioage, readiness, sleep, and shared_charts also carry Jasper's own `look` render spec — Whisper renders them natively (vitality blob, recovery ring, sleep hypnogram, ember inbox cards), so Jasper data in Whisper looks exactly like it does in Jasper.
    WRITABLE into Jasper: workouts, programs, meals, water, diet_plans, recipes (save/update/delete — a recipe saved from Whisper appears in Jasper under Nutrition → Recipes instantly; upserts by client_id), preferences (single object — POST merges only the keys sent), body, weight, blood_panels, goal_entries — plus charts: Whisper can post a chart or card into the user's Jasper "Shared with you" inbox (bio-age itself can never be written, only displayed). Every writable resource also supports DELETE by row id (charts: only Whisper's own posts), which emits a deletion event on the change feed.
    Coach tokens: Jasper re-verifies the coaching grant on EVERY call — ending the grant kills reads instantly, and blood requires a separately granted scope that Whisper's coach flow does not request. The coached client can see and revoke each "Whisper Coach" token from Jasper's own settings at any time (Whisper's Jasper card mirrors this with a Coach access list + a "what your coach sees" walkthrough). Read & write coaching grants additionally unlock coach WRITES into the client's Jasper (assign training programs, log meal/water corrections with one-tap undo, add goal entries, drop cards into their Shared inbox — never body, blood, or preference writes); read-only grants keep coaches strictly look-don't-touch.
    Consent is granular (Aug 2026): Jasper users can approve a SUBSET of requested scopes on the Allow card, and coaching invites can be accepted as view-only — so a token can hold fewer scopes than was requested. A missing_scope answer means the user chose not to share that resource; Whisper degrades that feature gracefully instead of retrying.
    One-call dashboard: GET /v1/dashboard assembles the ENTIRE coach dashboard Jasper's own coach view renders — profile, streaks, 14 days of readiness + sleep scores, vitals, workouts + PRs, meals + water, body + weight, bio age, blood panels, open goals, active programs + diet plans, and progress-photo metadata, plus a precomputed summary (latest readiness, last night's sleep, bio-age delta, weight, workouts this week, kcal today). Sections lock INDIVIDUALLY ({ locked, required_scope }) instead of failing the call — on coach tokens blood stays locked unless the client granted read:blood explicitly. THE DASHBOARD IS THE ONLY SOURCE on every Whisper coach surface: the Coach Studio roster preview chips, the full client dashboard, and the in-chat live card all render this exact payload (same 60s cache entry, change-feed hints force-refresh it) — there is NO legacy snapshot mixing, so the preview can never disagree with the panel; when the API is unreachable Whisper says so honestly instead of substituting local numbers. Polled at most once a minute per client.
    Weekly digest (Aug 17 2026): GET /v1/dashboard?period=week is the same dashboard over 7-day windows plus a digest block — this-week vs last-week deltas (readiness avg, sleep quality + duration, workouts + volume kg + PRs, kcal/day + meals, weight) and digest.highlights: ready-to-paste check-in sentences. Whisper's coach dashboard has a TODAY/WEEK DIGEST switch that renders it, with one-tap copy on every highlight — quote highlights verbatim for weekly check-ins, never recompute them.
    Change feed (Sept 15 2026): Jasper has PAUSED webhook push and new registrations (webhook_egress_unavailable) pending a pinned egress transport, so Whisper no longer registers hooks. Instead each coach dashboard refresh also pulls GET /v1/events/page for that client's token — commit-visible journal positions with a decimal-string next_cursor and a context that must be sent back together, 30-day retention — and verified journal events (workout.completed, meal.logged, weight.updated, bioage.updated, grocery.updated, <thing>.deleted …) light the LIVE strip on the coach client dashboard. This rides the same once-a-minute rail as the dashboard read; the first page only positions the cursor so history is never replayed as live. The signed-webhook verifier (X-Jasper-Signature HMAC, ±300s) stays in the code for when egress resumes.
    Marketplace (Aug 17 2026, LIVE in Whisper): Jasper hosts a public plan marketplace — GET /v1/marketplace browses coach-published program/diet-plan templates (preview at /v1/marketplace/<id> with the full plan_shapes payload; both public, no auth), POST /v1/marketplace publishes (the coach's own session JWT; stored server-side, not proof of native validation; re-publishing the same title updates in place; DELETE /v1/marketplace?id= unpublishes), POST /v1/marketplace/import copies a template into a Jasper with coach attribution and upsert-by-template-id semantics (the server rewrites payload.id/createdAt — importing twice never duplicates). Whisper's real UI: Coach Studio → Plan marketplace (search, kind filters, full-day previews, import into any accepted client or your own Jasper, unpublish your listings), a Marketplace button on every client dashboard that preselects that client as the import target, Coach tools → Program → "Also publish to the marketplace" (publishes the exact plan_shapes payload being assigned), and a marketplace chat action. price_usd is informational in v1 — no payment gate. Jasper also ships a self-hostable coach console (thejasperapp.com/coach-console.html) where coaches paste client tokens — tokens stay in their browser.
    Nutrition sync (Aug 17 2026): the grocery checklist is SHARED, id-addressed state — GET /v1/grocery_list returns the active plan's checklist with stable item ids + checked flags, POST {items:[{id,checked}]} checks off; these are the SAME rows Jasper's in-app checklist reads and writes, so checks converge in both directions (grocery.updated on the events feed, deduped ~30s) — Whisper's grocery sheets ARE that shared state (own list interactive; coach view interactive on write grants). POST /v1/diet_plans/generate is paused: 409 native_review_required, no generation or save. Never retry or substitute a direct AI provider. Use Jasper's reviewed native Nutrition flow. Recipes: GET/POST/DELETE /v1/recipes under the nutrition scopes — POST normalizes ingredients into Jasper's decode-safe shape server-side (never build the payload by hand), upserts by client_id, events recipe.saved/recipe.deleted; ingredient macros describe ONE serving of that ingredient, numberOfServings scales what the recipe uses, per-serving macros = totals ÷ servings, always derived. The water_cup look (catalog looks.water) is Jasper's animated glass spec — Whisper renders hydration exactly like Jasper, with tap-to-log cups on the user's own tracker.
    Plan authoring (plan_shapes): GET /v1/catalog publishes plan_shapes — the byte-exact payload contracts for POST /v1/programs and POST /v1/diet_plans: uuid string ids mirroring client_id, createdAt in Apple-epoch SECONDS as a number, program reps ALWAYS a string, notes present even when empty, goals from Jasper's fixed vocabulary, days[].meals[] for diet plans, groceryList optional (Jasper derives it when omitted). Preserve programming, trainingRevision, weeklyReviews, generationProfile, every workoutDays weekNumber/weekday/phase, and exercise catalogID/targetRIR/notes. Never flatten a multiweek sequence into a repeated week. Cloud storage is not proof of native validation, active-plan selection or applied changes; review must happen in Jasper.
    Units are SI (kg, ml, kcal, seconds); timestamps ISO 8601 UTC. When the user asks what Whisper can see or sync from Jasper, answer from THIS list.
    """

    // MARK: Plumbing

    private func persist(_ info: JasperConnection) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(try? encoder.encode(info), forKey: metaKey)
    }

    /// Clears UI synchronously; per-account credentials are never adopted by another owner.
    func accountDidChange() {
        connectionGeneration = UUID()
        isDisconnecting = false
        disconnectError = nil
        cachedSnapshot = nil
        lastLiveError = nil
        inFlightSnapshot?.cancel()
        inFlightSnapshot = nil
        state = .notConnected
        restore()
    }

    private func wipe() {
        connectionGeneration = UUID()
        isDisconnecting = false
        // Guide §09: honor the revocation even when secure cleanup fails — and say so.
        credentialCleanupFailed = !JasperConnectKeychain.clear()
        UserDefaults.standard.removeObject(forKey: metaKey)
        JasperEventPush.shared.forget(uid: stateOwner)
        cachedSnapshot = nil
        lastLiveError = credentialCleanupFailed
            ? "Jasper access ended, but the old token couldn't be removed from the Keychain. Sign out and back in to clear it."
            : nil
        inFlightSnapshot?.cancel()
        inFlightSnapshot = nil
        state = .notConnected
    }

    /// Direct PostgREST RPC with the user's OWN session (connect flow only).
    /// Internal: `JasperCoachConnect` mints per-client coach tokens through
    /// the same `jasper_connect_authorize` / `jasper_connect_revoke` RPCs.
    func rpc(_ name: String, params: [String: Any],
             jwt: String) async throws -> [String: Any] {
        let (data, status) = try await rpcData(name, params: params, jwt: jwt)
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status == 401 || status == 403 { throw JasperConnectError.notSignedIn }
        if !(200..<300).contains(status) {
            throw JasperConnectError.server((body["message"] as? String) ?? "Jasper Connect error (\(status)).")
        }
        return body
    }

    /// RPCs that return SETOF rows (e.g. `jasper_connect_connections`) —
    /// parses a top-level JSON array, or an array nested under common keys.
    func rpcRows(_ name: String, params: [String: Any],
                 jwt: String) async throws -> [[String: Any]] {
        let (data, status) = try await rpcData(name, params: params, jwt: jwt)
        if status == 401 || status == 403 { throw JasperConnectError.notSignedIn }
        guard (200..<300).contains(status) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw JasperConnectError.server((body?["message"] as? String) ?? "Jasper Connect error (\(status)).")
        }
        let any = try? JSONSerialization.jsonObject(with: data)
        if let rows = any as? [[String: Any]] { return rows }
        if let dict = any as? [String: Any] {
            for key in ["connections", "data", "rows", "tokens"] {
                if let rows = dict[key] as? [[String: Any]] { return rows }
            }
        }
        return []
    }

    private func rpcData(_ name: String, params: [String: Any],
                         jwt: String) async throws -> (Data, Int) {
        let context = try await JasperAccountSession.current()
        guard jwt == context.jwt else { throw CancellationError() }
        let url = JasperConnectConfig.supabaseURL.appendingPathComponent("rest/v1/rpc/\(name)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(JasperConnectConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        let (data, response) = try await session.data(for: request)
        try context.check()
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// REST data call with the stored jc_ token. 401 ⇒ the token was revoked
    /// or expired remotely — surface `.revoked` so callers can wipe/reconnect.
    /// `overrideToken` lets `JasperCoachConnect` reuse this exact URL builder
    /// (URLComponents — the query-encoding fix lives in ONE place) with a
    /// per-client coach token instead of the own-account one.
    func dataRequest(path: String, query: [URLQueryItem] = [], method: String,
                     payload: [String: Any]?, overrideToken: String? = nil,
                     timeout: TimeInterval? = nil, idempotencyKey: String? = nil) async throws -> Data {
        if path == "/v1/diet_plans/generate" { throw JasperConnectError.server(Self.nativeReviewMessage) }
        let epoch = connectionGeneration
        let account = AccountStorage.generation
        let context = try await JasperAccountSession.current()
        guard account == AccountStorage.generation, epoch == connectionGeneration else { throw CancellationError() }
        if overrideToken == nil, isDisconnecting || connection == nil { throw JasperConnectError.notConnected }
        guard let token = overrideToken ?? JasperConnectKeychain.load() else {
            throw JasperConnectError.notConnected
        }
        if let overrideToken, !JasperCoachConnect.shared.owns(token: overrideToken) { throw CancellationError() }
        // Build with URLComponents — URL.appending(path:) percent-encodes "?"
        // and "&", which mangled every query-string read into a request for a
        // resource literally named "workouts?since=…" (the bug behind the
        // "couldn't reach Jasper" preview while /v1/me worked fine).
        guard var components = URLComponents(url: JasperConnectConfig.apiBase,
                                             resolvingAgainstBaseURL: false) else {
            throw JasperConnectError.server("Bad Jasper Connect base URL.")
        }
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw JasperConnectError.server("Couldn't build the Jasper request URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = min(timeout ?? 30, 60)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Client-Request-Id")
        if let idempotencyKey, method != "GET", JasperConnectConfig.supportsIdempotency(path: path) {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let (data, response) = try await session.data(for: request)
        try context.check()
        guard epoch == connectionGeneration else { throw CancellationError() }
        if overrideToken == nil, token != JasperConnectKeychain.load() { throw CancellationError() }
        if let overrideToken, !JasperCoachConnect.shared.owns(token: overrideToken) { throw CancellationError() }
        let http = response as? HTTPURLResponse
        if let http { noteContract(http) }
        let status = http?.statusCode ?? 0
        guard !(200..<300).contains(status) else { return data }
        let failure = JasperConnectFailure(status: status, response: http, data: data)
        lastFailure = failure
        // Guide §08: any 401 (invalid_token, coach_grant_revoked) and 409
        // connection_changed mean the credential is dead — wipe, never retry.
        if failure.isRevocation {
            if overrideToken == nil { wipe() }
            throw JasperConnectError.revoked
        }
        if status == 429 { throw JasperConnectError.rateLimited(retryAfter: failure.retryAfter, requestID: failure.requestID) }
        throw JasperConnectError.server(failure.message)
    }

    /// POST /v1/tokens/revoke {token_id} with the holder's own session JWT
    /// (guide §02: session JWTs manage connections, jc_ tokens read data).
    /// A host without the route falls back to the shared project's
    /// `jasper_connect_revoke` RPC. True only when Jasper confirmed it.
    func revokeToken(id tokenID: String, context: JasperAccountSession) async throws -> Bool {
        try context.check()
        var request = URLRequest(url: JasperConnectConfig.apiBase.appendingPathComponent("v1/tokens/revoke"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(context.jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token_id": tokenID])
        let (data, response) = try await session.data(for: request)
        try context.check()
        let http = response as? HTTPURLResponse
        if let http { noteContract(http) }
        let status = http?.statusCode ?? 0
        if status == 404 || status == 405 {
            let body = try await rpc("jasper_connect_revoke", params: ["p_id": tokenID], jwt: context.jwt)
            return body["ok"] as? Bool == true
        }
        guard (200..<300).contains(status) else {
            let failure = JasperConnectFailure(status: status, response: http, data: data)
            lastFailure = failure
            if status == 401 { throw JasperConnectError.notSignedIn }
            if status == 429 { throw JasperConnectError.rateLimited(retryAfter: failure.retryAfter, requestID: failure.requestID) }
            throw JasperConnectError.server(failure.message)
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return body["ok"] as? Bool == true || body["revoked"] as? Bool == true
    }

    /// Current explicit-scope authorization; never falls back to legacy broad access.
    func authorize(appName: String, scopes: [String], clientID: String? = nil,
                   context: JasperAccountSession) async throws -> [String: Any] {
        try context.check()
        var payload: [String: Any] = ["app_name": appName, "scopes": scopes]
        if let clientID { payload["client_user_id"] = clientID }
        var request = URLRequest(url: JasperConnectConfig.apiBase.appendingPathComponent("v1/authorize"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(context.jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        try context.check()
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let http = response as? HTTPURLResponse
        if let http { noteContract(http) }
        guard let http, (200..<300).contains(http.statusCode) else {
            let failure = JasperConnectFailure(status: http?.statusCode ?? 0, response: http, data: data)
            lastFailure = failure
            if http?.statusCode == 429 { throw JasperConnectError.rateLimited(retryAfter: failure.retryAfter, requestID: failure.requestID) }
            throw JasperConnectError.server(body["error"] == nil ? "Couldn't authorize Jasper. Please try again." + failure.reference : failure.message)
        }
        return body
    }

    private func friendly(_ error: Error) -> String {
        if let known = error as? JasperConnectError {
            return known.errorDescription ?? "Something went wrong."
        }
        return (error as NSError).domain == NSURLErrorDomain
            ? "You're offline — try again when you have a connection."
            : error.localizedDescription
    }
}
