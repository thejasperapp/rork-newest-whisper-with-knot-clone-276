# Whisper × Jasper Connect — the one-click "Connect Jasper" drop-in

This is the **copy-paste implementation of the Connect Jasper button** for the
Whisper codebase. One tap → Whisper holds a full-access Jasper Connect token
(`jc_…`). No codes, no pasting, no approval screens — the account link IS the
consent (see `WHISPER_LINKING.md` §0).

> **When to use Connect vs. the direct bridge:** for in-app UI reads, keep the
> direct shared-Supabase path (`jasper_*` tables + Realtime) — it's faster and
> free of token plumbing. Use the Connect token when you want the **uniform REST
> API** (server-side features, exports, integrations) and especially to **POST
> into Jasper**: workouts, meals, blood panels, and Jasper-format charts that
> land in the user's "Shared with you" inbox.

Two files, one integration point (the session JWT provider):

| File | What it is |
|---|---|
| `Services/JasperConnectClient.swift` | Token lifecycle (authorize → Keychain → validate → revoke) + typed REST helpers |
| `Views/ConnectJasperButton.swift` | The button. States: not connected / connecting / connected / error |

---

## What's new — August 16, 2026 (read this first)

Three contract changes shipped today. Nothing breaks existing Whisper code,
but two of them change what you may safely *assume*:

1. **Users can now trim scopes at Allow.** The Allow card in Jasper (the
   request → allow → claim flow) grew a **"Choose what to share"** picker —
   the user can approve a *subset* of the scopes a request asked for
   (server-validated in `jasper_connect_respond`; on coach full-access
   requests the blood group defaults to OFF). A claim can therefore mint a
   token with FEWER scopes than requested. Whisper's one-click authorize is
   untouched — standing consent still mints exactly what it asks for
   (`all`). **Action:** anywhere you use the request flow, read `scopes` off
   the claim response (or `GET /v1/me`) and treat a per-resource 403
   `missing_scope` as "the user chose not to share this" — degrade the
   feature, don't retry or error-loop.
2. **Coach invites can be downgraded to view-only at consent.** The client's
   consent screen now has a "Let them make changes" toggle — a `read_write`
   invite may land as a `read` grant
   (`redeem_coach_grant_code(p_code, p_scope)`; downgrade only, never
   upgrade). **Action:** never assume invite scope == effective scope; the
   `my_clients()` row and the 403 `coach_grant_read_only` backstop are the
   truth.
3. **Diet plans now carry the grocery checklist.** Every `diet_plans` read
   ships `payload.groceryList` — the exact categorized checklist Jasper
   renders in-app (and shares over iMessage). Render it as-is — decode
   snippet in §4, full shape in §8 fact 9. Never re-derive groceries from
   ingredients.

Also: public docs now advertise the branded origin
`https://www.thejasperapp.com/api/*` — an alias that proxies to the same
worker. Your configured `https://jaspyjaz-backend.rork.app` keeps working
unchanged; no action needed.

---

## 0. How the one-click works (10 seconds)

1. The signed-in Whisper user taps **Connect Jasper**.
2. Whisper calls the `jasper_connect_authorize` RPC **with the user's own
   Supabase session JWT** (same project, same `auth.uid()`).
3. Postgres resolves the Jasper account via `jasper_uid_for()` (account link, or
   self for same-account users), mints a `jc_…` token with the `all` scope
   (full read + write), and returns it **in the same call**.
4. Whisper stores the raw token in the **Keychain** (it is shown/returned exactly
   once — only its sha256 exists server-side) and the non-secret metadata
   (token id, scopes, username) in `UserDefaults` under `jasper_connect_meta_v1`.
5. Re-tapping later **rotates** the previous token for the same holder+app
   (name matched case-insensitively) — reconnect is always safe and never
   stacks toward the 20-connection cap.
6. The token **never expires** — it lives until revoked or rotated. Disconnect
   (either side!) revokes instantly. The client detects a remote revoke on the
   next call (401) and flips back to "Connect Jasper".

**Identity prerequisite:** if the Whisper sign-in is a *different* account and
no account link exists, `jasper_uid_for()` falls back to the user's own (empty)
graph — the token will "work" but see nothing. Resolve identity first
(`WHISPER_LINKING.md` §1) and only show this button once linked or same-account.
The authorize response helps you detect this: `user.linked` is `true` when an
account link (or coach grant) resolved a *different* owner account, and
`user.username` is present whenever the owner has a real Jasper profile.
`username` null/missing **and** `linked:false` ⇒ warn — the token points at a
graph with no Jasper presence.

---

## 1. `Services/JasperConnectClient.swift`

```swift
import Foundation
import Security

// MARK: - Config

enum JasperConnectConfig {
    /// Same Supabase project Whisper already uses.
    static let supabaseURL = URL(string: "https://uryyyegnbtlmyhqlgndy.supabase.co")!
    /// The public anon key (same constant Whisper already holds for its own client).
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyeXl5ZWduYnRsbXlocWxnbmR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyMzM3MDcsImV4cCI6MjA5MDgwOTcwN30.fBo6K9yNHmk1nTArspc5ByMsWEiI2SahCFk6Mdp7qUQ"
    /// Jasper Connect REST surface (catalog: GET /v1/catalog).
    static let apiBase = URL(string: "https://jaspyjaz-backend.rork.app")!

    /// THE ONE INTEGRATION POINT.
    /// Return the signed-in user's CURRENT Supabase access token.
    /// supabase-swift: `try await supabase.auth.session.accessToken`
    /// Custom auth stack: return whatever you attach as `Authorization: Bearer`
    /// to your own PostgREST calls.
    static var sessionJWT: @Sendable () async throws -> String = {
        throw JasperConnectError.notWired
    }
}

// MARK: - Models

struct JasperConnection: Codable, Equatable {
    let tokenID: UUID          // jasper_connect_tokens.id — needed for revoke
    let tokenPrefix: String    // "jc_12345678" — safe to display
    let appName: String
    let scopes: [String]
    let kind: String           // "app" | "coach"
    let username: String?
    let displayName: String?
    let connectedAt: Date

    var hasFullAccess: Bool { scopes.contains("all") }
    var scopeSummary: String {
        hasFullAccess ? "Full access" : "\(scopes.count) scopes"
    }
}

enum JasperConnectState: Equatable {
    case notConnected
    case connecting
    case connected(JasperConnection)
    case error(String)
}

struct JasperWriteReceipt: Decodable {
    let ok: Bool
    let resource: String?
    let id: UUID?
    let clientID: String?

    enum CodingKeys: String, CodingKey {
        case ok, resource, id
        case clientID = "client_id"
    }
}

enum JasperConnectError: LocalizedError {
    case notWired
    case notSignedIn
    case notConnected
    case revoked
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notWired: return "JasperConnectConfig.sessionJWT is not wired up."
        case .notSignedIn: return "Sign in to Whisper first."
        case .notConnected: return "Jasper isn't connected yet."
        case .revoked: return "This connection was revoked. Reconnect to continue."
        case .server(let message): return message
        }
    }
}

// MARK: - Keychain (raw token only — metadata lives in UserDefaults)

private enum JasperConnectKeychain {
    private static let service = "jasper.connect"
    private static let account = "jc_token"

    static func save(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
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

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Client

@MainActor
@Observable
final class JasperConnectClient {
    static let shared = JasperConnectClient()

    private(set) var state: JasperConnectState = .notConnected

    private let metaKey = "jasper_connect_meta_v1"
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
        if case .connected(let info) = state { return info }
        return nil
    }

    // MARK: Lifecycle

    /// Rehydrate from Keychain + UserDefaults, then verify in the background
    /// so a remotely-revoked token flips the UI back to "Connect Jasper".
    func restore() {
        guard JasperConnectKeychain.load() != nil,
              let data = UserDefaults.standard.data(forKey: metaKey),
              let meta = try? decoder.decode(JasperConnection.self, from: data) else {
            state = .notConnected
            return
        }
        state = .connected(meta)
        Task { await validate() }
    }

    /// ONE CLICK. Mints (or rotates) a full-access token via the account link.
    /// Pass `clientUserID` to connect as a COACH to that client instead
    /// (requires an active coach grant — read_write since we ask full access).
    func connect(clientUserID: UUID? = nil) async {
        state = .connecting
        do {
            let jwt = try await JasperConnectConfig.sessionJWT()
            var params: [String: Any] = ["p_app_name": "Whisper"]
            if let clientUserID { params["p_client"] = clientUserID.uuidString }
            let body = try await rpc("jasper_connect_authorize", params: params, jwt: jwt)

            guard body["ok"] as? Bool == true,
                  let raw = body["token"] as? String,
                  let idString = body["id"] as? String,
                  let tokenID = UUID(uuidString: idString) else {
                let message = (body["error"] as? String) ?? "Jasper didn't return a token."
                let hint = body["hint"] as? String
                state = .error([message, hint].compactMap { $0 }.joined(separator: " "))
                return
            }

            let user = body["user"] as? [String: Any]
            let info = JasperConnection(
                tokenID: tokenID,
                tokenPrefix: (body["token_prefix"] as? String) ?? String(raw.prefix(11)),
                appName: (body["app_name"] as? String) ?? "Whisper",
                scopes: (body["scopes"] as? [String]) ?? ["all"],
                kind: (body["kind"] as? String) ?? "app",
                username: user?["username"] as? String,
                displayName: user?["display_name"] as? String,
                connectedAt: Date()
            )
            JasperConnectKeychain.save(raw)
            persist(info)
            state = .connected(info)
        } catch {
            state = .error(friendly(error))
        }
    }

    /// Revoke server-side (works even if the token already died), then wipe.
    func disconnect() async {
        if let info = connection, let jwt = try? await JasperConnectConfig.sessionJWT() {
            _ = try? await rpc("jasper_connect_revoke",
                               params: ["p_id": info.tokenID.uuidString], jwt: jwt)
        }
        wipe()
    }

    /// GET /v1/me — detects remote revoke/expiry and clears local state on 401.
    func validate() async {
        guard connection != nil else { return }
        do {
            _ = try await dataRequest(path: "/v1/me", method: "GET", payload: nil)
        } catch JasperConnectError.revoked {
            wipe()
        } catch {
            // Network blips keep the cached connected state — never punish offline.
        }
    }

    // MARK: Reads — GET /v1/<resource> → { ok, resource, count, data: [...] }

    /// Decoded rows. Model each resource with a small Decodable struct.
    func rows<T: Decodable>(_ resource: String, of type: T.Type,
                            since: Date? = nil, limit: Int? = nil,
                            cursor: Int? = nil) async throws -> [T] {
        struct Envelope<Row: Decodable>: Decodable { let data: [Row] }
        let data = try await read(resource, since: since, limit: limit, cursor: cursor)
        return try decoder.decode(Envelope<T>.self, from: data).data
    }

    /// Raw envelope bytes when you'd rather JSONSerialization your way through.
    func read(_ resource: String, since: Date? = nil, limit: Int? = nil,
              cursor: Int? = nil) async throws -> Data {
        var query: [String] = []
        if let since { query.append("since=\(ISO8601DateFormatter().string(from: since))") }
        if let limit { query.append("limit=\(limit)") }
        if let cursor { query.append("cursor=\(cursor)") }
        let suffix = query.isEmpty ? "" : "?" + query.joined(separator: "&")
        return try await dataRequest(path: "/v1/\(resource)\(suffix)", method: "GET", payload: nil)
    }

    // MARK: Writes — POST /v1/<resource> → { ok, resource, id, client_id }

    /// Upserts by payload `client_id` (send a stable UUID string for idempotency).
    @discardableResult
    func post(_ resource: String, _ payload: [String: Any]) async throws -> JasperWriteReceipt {
        let data = try await dataRequest(path: "/v1/\(resource)", method: "POST", payload: payload)
        return try decoder.decode(JasperWriteReceipt.self, from: data)
    }

    /// Post a Jasper-format chart / bio-age card into the user's Shared inbox.
    /// kind: "chart" (needs `chart` spec) | "bioage" (needs `chart`) | "card" (text-only).
    @discardableResult
    func postChart(title: String, kind: String = "chart",
                   chart: [String: Any]? = nil, note: String? = nil) async throws -> JasperWriteReceipt {
        var payload: [String: Any] = ["title": title, "kind": kind]
        if let chart { payload["chart"] = chart }
        if let note { payload["note"] = note }
        return try await post("charts", payload)
    }

    // MARK: Plumbing

    private func persist(_ info: JasperConnection) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(try? encoder.encode(info), forKey: metaKey)
    }

    private func wipe() {
        JasperConnectKeychain.clear()
        UserDefaults.standard.removeObject(forKey: metaKey)
        state = .notConnected
    }

    /// Direct PostgREST RPC with the user's OWN session (connect flow only).
    private func rpc(_ name: String, params: [String: Any],
                     jwt: String) async throws -> [String: Any] {
        let url = JasperConnectConfig.supabaseURL.appendingPathComponent("rest/v1/rpc/\(name)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(JasperConnectConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status == 401 || status == 403 { throw JasperConnectError.notSignedIn }
        if !(200..<300).contains(status) {
            throw JasperConnectError.server((body["message"] as? String) ?? "Jasper Connect error (\(status)).")
        }
        return body
    }

    /// REST data call with the stored jc_ token. 401 ⇒ the token was revoked
    /// or expired remotely — surface `.revoked` so callers can wipe/reconnect.
    private func dataRequest(path: String, method: String,
                             payload: [String: Any]?) async throws -> Data {
        guard let token = JasperConnectKeychain.load() else {
            throw JasperConnectError.notConnected
        }
        var request = URLRequest(url: JasperConnectConfig.apiBase.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw JasperConnectError.revoked }
        if !(200..<300).contains(status) {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw JasperConnectError.server((body?["error"] as? String) ?? "Jasper Connect error (\(status)).")
        }
        return data
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
```

---

## 2. `Views/ConnectJasperButton.swift`

Matches the Whisper design spec (`WHISPER_DESIGN.md`): glass over the warm
gradient, very round corners, ink text, the warm-orange accent, light haptics.

```swift
import SwiftUI

/// Drop into Settings (or the identity screen). Self-contained:
/// ConnectJasperButton()
struct ConnectJasperButton: View {
    @State private var client = JasperConnectClient.shared
    @State private var showDisconnectConfirm = false
    @Environment(\.colorScheme) private var colorScheme

    private let jasperOrange = Color(red: 0.953, green: 0.565, blue: 0.341)

    var body: some View {
        Group {
            switch client.state {
            case .notConnected:
                connectButton
            case .connecting:
                statusCard {
                    ProgressView().controlSize(.small)
                    Text("Connecting to Jasper…")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            case .connected(let info):
                connectedCard(info)
            case .error(let message):
                errorCard(message)
            }
        }
        .animation(.spring(duration: 0.35), value: client.state)
        .confirmationDialog("Disconnect Jasper?", isPresented: $showDisconnectConfirm,
                            titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task { await client.disconnect() }
            }
        } message: {
            Text("Whisper loses access instantly. You can reconnect with one tap.")
        }
    }

    // MARK: Not connected — the one-tap moment

    private var connectButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                await client.connect()
                if case .connected = client.state {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        } label: {
            HStack(spacing: 12) {
                jasperMark
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Jasper")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("One tap — full read & write access")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(jasperOrange)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.10 : 0.075),
                                  lineWidth: 0.8)
            }
            .shadow(color: jasperOrange.opacity(0.18), radius: 22, y: 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: Connected

    private func connectedCard(_ info: JasperConnection) -> some View {
        HStack(spacing: 12) {
            jasperMark
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Jasper connected")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                }
                Text(subtitle(for: info))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                Button {
                    Task { await client.validate() }
                } label: {
                    Label("Test connection", systemImage: "bolt.badge.checkmark")
                }
                Button {
                    Task { await client.connect() }   // rotates the token safely
                } label: {
                    Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) {
                    showDisconnectConfirm = true
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: .circle)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.green.opacity(0.25), lineWidth: 0.8)
        }
    }

    // MARK: Error

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await client.connect() }
            } label: {
                Text("Try again")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(jasperOrange.opacity(0.16), in: .capsule)
                    .foregroundStyle(jasperOrange)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
    }

    // MARK: Bits

    private var jasperMark: some View {
        Text("J")
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(
                LinearGradient(colors: [jasperOrange,
                                        Color(red: 0.965, green: 0.725, blue: 0.541)],
                               startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: 12)
            )
    }

    private func subtitle(for info: JasperConnection) -> String {
        var parts: [String] = []
        if let username = info.username { parts.append("@\(username)") }
        parts.append(info.scopeSummary)
        parts.append(info.tokenPrefix + "…")
        return parts.joined(separator: " · ")
    }
}
```

---

## 3. Wire-up (two steps)

**Step 1 — at app start** (wherever Whisper configures its Supabase client):

```swift
// supabase-swift:
JasperConnectConfig.sessionJWT = {
    try await supabase.auth.session.accessToken
}
```

**Step 2 — drop the button** into Settings / the Jasper section:

```swift
Section("Jasper") {
    ConnectJasperButton()
}
```

That's it. `JasperConnectClient.shared` is usable anywhere after that.

---

## 4. Using the token

```swift
let jasper = JasperConnectClient.shared

// READ — decoded rows (model only the fields you need)
struct WorkoutRow: Decodable {
    let id: UUID
    let title: String?
    let total_volume_kg: Double?
    let performed_at: Date
}
let workouts = try await jasper.rows("workouts", of: WorkoutRow.self, limit: 20)

// WRITE — log a meal INTO Jasper (idempotent via client_id)
try await jasper.post("meals", [
    "client_id": UUID().uuidString,       // reuse the same UUID to upsert
    "name": "Post-workout shake",
    "meal_type": "snack",
    "calories": 420, "protein_g": 42, "carbs_g": 38, "fat_g": 12,
    "logged_at": ISO8601DateFormatter().string(from: .now),
])

// POST A CHART into the user's Shared inbox (Jasper chart spec)
try await jasper.postChart(
    title: "Weekly training volume",
    kind: "chart",
    chart: [
        "type": "bar",
        "unit": "kg",
        "points": [                        // y MUST be a number — it drives the series
            ["label": "Mon", "y": 5200],
            ["label": "Wed", "y": 6100],
            ["label": "Fri", "y": 5800],
        ],
    ],
    note: "Volume up 9% — nice week."
)

// GROCERY CHECKLIST — every diet_plans row carries the in-app list. Render as-is.
struct DietPlanRow: Decodable {
    struct Payload: Decodable { let groceryList: GroceryList? }
    struct GroceryList: Decodable {
        struct Category: Decodable { let name: String; let items: [Item] }
        struct Item: Decodable { let name: String; let quantity: String; let usedInMeals: Int }
        let planName: String
        let itemCount: Int
        let categories: [Category]  // Proteins · Dairy & Eggs · Fruits & Vegetables · Grains & Bread · Pantry · …
    }
    let id: UUID
    let name: String?
    let is_active: Bool?
    let payload: Payload?
}
let plans = try await jasper.rows("diet_plans", of: DietPlanRow.self, limit: 5)
let groceries = plans.first(where: { $0.is_active == true })?.payload?.groceryList
// nil groceryList = a third-party row that omitted it — only then fall back to payload.days ingredients.
```

Envelopes: reads return `{ ok, resource, count, data: [...] }`; writes return
`{ ok, resource, id, client_id }`. Full resource list: `GET /v1/catalog` (the
machine-readable source of truth) or the appendix in §8 below. Note that
`https://www.thejasperapp.com/connect` is a JS-rendered page — fetching its raw
HTML returns only the app shell; use the catalog or this doc instead.

**Coach mode:** connecting *as a coach* to a client is the same client with one
argument — `await client.connect(clientUserID: clientUID)` — and requires an
active `read_write` coach grant from that client (else you get the
`no_active_coach_grant` error with a hint to use the request flow instead).

---

## 5. The Jasper chart spec (authoritative)

What `POST /v1/charts` validates server-side, and what Jasper's inbox renders.

**Envelope** — `{ title, kind?, chart?, note? }`

- `title` — **required** (else 400 `title required`). This is the row title; a
  `title` inside `chart` is ignored.
- `kind` — `chart` (default) · `bioage` · `card`. Unknown values coerce to `chart`.
- `chart` — JSON object, **required unless `kind:"card"`** (else 400
  `chart object required … or use kind:card for text-only`).
- `note` — optional text, shown under the chart.

**The `chart` object** — every field optional, decoded leniently (bad fields are
dropped, never rejected):

| Field | Type | Notes |
|---|---|---|
| `type` | string | `"line"` or `"bar"` hint |
| `unit` | string | display unit — `"kg"`, `"yrs"`, `"bpm"`… |
| `points` | `[{ y, x?, label? }]` | **`y` must be a number** — it drives the series. `x` is numeric too (epoch seconds or ordinal index); strings in `x` are silently dropped — put display text in `label`. |
| `values` | `[number]` | flat alternative to `points` (preferred by the renderer) |
| `labels` | `[string]` | pairs with `values` |

The inbox preview renders the **last 24 numbers** from `values`, falling back to
`points[].y`. A points array with no numeric `y` renders an *empty* chart — the
#1 mistake to avoid (e.g. `{"label":"Mon","value":5200}` shows nothing; use `y`).

**`kind:"bioage"`** is a display tag — the card gets the hourglass treatment. It
does **not** feed the bio-age engine (nothing can), and it still requires a
`chart` object. Recommended: `{ "unit": "yrs", "values": […bio-age per day…] }`.

**`kind:"card"`** is text-only — `title` + `note`, no `chart` needed.

Every accepted post lands in Settings → Jasper Connect → **"Shared with you"**
with a NEW badge, and emits `chart.posted` on the change feed.

### Deleting rows

`DELETE /v1/<resource>?id=<row id or client_id>` removes one logical row —
same scope as POST. Works on `workouts`, `programs`, `meals`, `water`,
`diet_plans`, `preferences`, `body`, `weight`, `blood_panels`,
`goal_entries`, and `charts` (your **own** posts only). Response:
`{ ok, resource, id, deleted: 0|1 }` — `deleted: 0` means no matching row
(already gone; deletes are idempotent by nature). A real deletion emits a
`<thing>.deleted` event on the change feed so every consumer converges.

### Native looks — draw it like Jasper draws it

Reads for `bioage`, `readiness`, `sleep`, and `shared_charts` carry a
top-level **`look`** object — the machine-readable spec of the exact visual
Jasper renders for that data. The full set (plus the `brand` palette) is
published in `GET /v1/catalog` under `looks`. Render these instead of generic
charts and bio-age in Whisper looks like bio-age in Jasper.

**`bioage` → the vitality blob** (`look.style: "vitality_blob"`)

- `t = (clamp(delta_years, −10, 10) + 10) / 20` — 0 = 10y younger (green),
  0.5 = on par (teal), 1 = 10y older (red). `delta_years` is on every row.
- Three gradient stops, per-channel sRGB lerp between palettes:
  younger `#4DF28C #1ACC80 #0D8C73` · on-par `#33D9CC #26A6D9 #1A73B3` ·
  older `#FF734D #F28C33 #CC3340`. `t < 0.5` lerps younger→on-par with
  `t/0.5`, else on-par→older with `(t−0.5)/0.5`.
- Outline: 80-point closed path,
  `r(θ) = R · (1 + w·(0.10·sin(3θ+time) + 0.06·sin(5θ−1.3·time) + 0.05·sin(2θ+0.7·time)))`,
  `w` = 1.0 hero / 0.55 compact. Three layers (scale/phase/opacity/speed:
  `0.96/0/0.30/0.6`, `0.86/1.7/0.45/0.9`, `0.74/3.3/0.95/1.25`), each filled
  with the 3-stop linear gradient top-left → bottom-right; a white 22%
  highlight blob (radius 0.42R, offset −0.12R/−0.14R) gives the glassy core;
  a big blurred radial glow sits behind (stop1 @ 55% → stop2 @ 18% → clear).
  The age number sits on top — bold rounded face, white — with the delta chip
  under it. Accent tint by `t`: `< 0.5 → #40D98C`, `< 0.62 → #33C7D1`, else
  `#FF8052`.

Copy-paste canvas outline:

```js
function blobPath(ctx, cx, cy, R, time, w = 1) {
  ctx.beginPath();
  for (let i = 0; i <= 80; i++) {
    const a = (i / 80) * 2 * Math.PI;
    const wob = 0.10 * Math.sin(3 * a + time)
              + 0.06 * Math.sin(5 * a - 1.3 * time)
              + 0.05 * Math.sin(2 * a + 0.7 * time);
    const r = R * (1 + wob * w);
    const x = cx + Math.cos(a) * r, y = cy + Math.sin(a) * r;
    i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
  }
  ctx.closePath();
}
```

**`readiness` → the recovery ring** — conic gradient `#5CDBB8 → #3394E0 →
#5CDBB8` from 12 o'clock clockwise, round caps, stroke ≈ 9.4% of diameter,
track = foreground @ 10%, sweep = `score/100`, soft mint glow. Score color
thresholds (number, dots, component bars): `≥ 75 → #5CDBB8` · `≥ 50 →
#3394E0` · else `#F26659`.

**`sleep` → the hypnogram** — four lanes top→bottom: `awake #FF9500` · `rem
#32ADE6` · `core #5856D6` (= `light_seconds`) · `deep #AF52DE`; rounded stage
bands across `started_at → ended_at`; `quality_score` in a small indigo ring
(`#5856D6` on a 15% track). Indigo is the sleep accent.

**`shared_charts` → the inbox card** — Jasper draws YOUR posts with the ember
gradient `#F39057 → #E76F3A` on a cream `#FBF4E4` card with ink `#211C1A`
text — the `look` tells you exactly what the user sees.

30fps is plenty for the blob; a static frame (fixed `time`) is a valid render
for cards and exports.

---

## 6. Behavior map (what happens when…)

| Situation | Behavior |
|---|---|
| Same account in both apps | Authorize succeeds instantly (owner = self) |
| Linked accounts (`account_links`) | Authorize succeeds instantly (owner = linked Jasper uid) |
| Different sign-ins, NO link | Token mints against the user's own **empty** graph — gate the button behind identity resolution (`WHISPER_LINKING.md` §1) |
| Re-tap Connect / Reconnect | Server rotates: old token revoked, new one returned |
| User disconnects in Whisper | `jasper_connect_revoke` + local wipe — instant |
| User revokes in Jasper (Settings → Jasper Connect) | Next Whisper call gets 401 → client wipes → button returns to "Connect Jasper" |
| 20 active connections on the Jasper account | Authorize fails with "too many active connections" — surface the message |
| Coach without a grant | `no_active_coach_grant` (403) — use `jasper_connect_request` → client taps Allow in Jasper → `jasper_connect_claim` |
| User trims scopes on the Allow card | Claim mints exactly the approved subset — read `scopes` off the claim response; un-shared resources return 403 `missing_scope` |
| Client downgrades a coach invite to view-only | Grant lands as `read` — writes fail 403 `coach_grant_read_only`; `my_clients()` shows the effective scope |
| Writing `bioage` | Impossible, by design — post blood/body data and let the calibrated engine move it; share bio-age **cards** via `postChart(kind: "bioage")` |

---

## 7. Do / Don't

**Do**
- Store the raw `jc_` token in the **Keychain only** — never UserDefaults, never logs.
- Send a stable `client_id` UUID on writes so retries upsert instead of duplicate.
- Keep using the direct `jasper_*` table reads for in-app UI; the token is for
  the REST surface and for **posting into Jasper**.
- Show the button only after identity is resolved (linked or same-account).
- Read the granted `scopes` off authorize/claim responses (or `GET /v1/me`) —
  users can approve a subset of what you requested (Aug 2026).

**Don't**
- Don't ask the user to copy/paste anything — that's the manual flow, for other apps.
- Don't cache the token in memory longer than needed for a call — read it from
  the Keychain helper each time (already how the client works).
- Don't retry a 401 — it means revoked/expired; wipe and offer reconnect.
- Don't try to write bio-age. It will never work. (`write:blood` + `write:body`
  are the inputs; the engine does the rest.)
- Don't re-derive grocery lists from plan ingredients — `payload.groceryList`
  on `diet_plans` is the canonical checklist Jasper renders.

---

## 8. Contract facts — confirmed answers for the Whisper team

1. **App name.** `p_app_name: "Whisper"` (exact case) is canonical — it's what
   the drop-in sends. The server trims + caps at 60 chars and matches rotation
   **case-insensitively** per holder, so re-taps always rotate the previous
   token instead of stacking. The 20-connection cap counts distinct holder+app
   pairs — Whisper occupies exactly one slot.
2. **Token lifetime.** Tokens minted by one-click authorize **and** the
   request→claim flow **never expire** (`expires_at` is null). They die only by
   revoke (either side) or rotation (re-connect). Only manually-minted keys can
   carry an expiry — `GET /v1/me` returns `expires_at` if you ever hold one.
   Treating any 401 as revoked-and-wipe is exactly right.
3. **/connect page.** It's a client-rendered SPA — raw HTML fetches see only the
   shell (the full content is there in a browser). The machine-readable source
   of truth is `GET /v1/catalog`, which now also states the TTL, rate limits,
   and the chart spec. The full resource table is in the appendix below, so
   this doc is self-sufficient.
4. **`user.username`.** Populated whenever the token's owner has a Jasper
   profile row. The response also carries **`user.linked`** (bool): `true` = an
   account link or coach grant resolved a *different* owner account. Warning
   rule: `username` null/missing **and** `linked:false` ⇒ unlinked sign-in /
   no Jasper presence — warn before relying on the token. When `username` is
   present, show "Connected as @username" so users can confirm the right
   account got linked (the sample button's subtitle already does).
5. **Rate limits.** None enforced today — the worker never returns 429 and the
   only cap is `limit ≤ 200` rows per page (default 100). Platform limits sit
   far above normal use. Politeness contract: keep sustained traffic under
   ~1 req/s and poll `/v1/events` no more often than every 60 s. 429 is
   reserved for future abuse control — back off if you ever see it.
6. **Native looks.** Every `bioage`, `readiness`, `sleep`, and `shared_charts`
   read carries a `look` render spec (full set + `brand` palette in
   `GET /v1/catalog` → `looks`). Render those instead of generic charts — the
   blob / ring / hypnogram recipes are in §5 → "Native looks".
7. **Coach tokens — the exact contract.**
   - *Rotation keying:* per **(holder, owner, app_name)** — app name matched
     case-insensitively. Distinct owners never cross-rotate, so one canonical
     name across all your coach connects is safe (per-client names work too).
     Re-authorize always **rotates** the previous token for that pair —
     nothing ever stacks toward the 20-token cap.
   - *Grant check:* `authorize(p_client)` verifies `coach_grants`
     (status `active`). Read-only grants CAN mint — read scopes only; `all`
     or any `write:*` requires a `read_write` grant (the 403 hint says so).
     `user{}` always carries the client's identity with **`linked:true`** —
     on one-click authorize AND on request→claim.
   - *Blood by default:* on coach tokens the `all` wildcard **never** covers
     `read:blood`/`write:blood`. Send the explicit scope in `p_scopes` when
     the client wants you on blood work; otherwise blood rows AND blood
     events are filtered (403 with a hint on direct access). Applies to
     already-minted coach tokens too.
   - *Server backstop:* the standing grant is re-verified on **every call**
     (reads, writes, deletes, `/v1/me`). Grant killed by either side →
     instant **401 `coach_grant_revoked`**; a trigger also revokes the token
     rows so both sides' lists tidy up. Grant downgraded to read-only → reads
     keep working, writes/deletes return **403 `coach_grant_read_only`**.
     Revoking on your side is good hygiene, but the server guarantees it.
   - *Client visibility:* clients see every coach token — with the coach's
     @username resolved — in Jasper → Settings → Jasper Connect, and can
     revoke any of them there.
8. **Row schemas + the new surface.** `GET /v1/catalog` now publishes
   **`fields`** (exact read row keys) and **`write_fields`** (accepted POST
   keys) per resource, plus `deletable`. New resources: **`preferences`**
   (units / theme / dashboard order — single object; `read:preferences` /
   `write:preferences`; POST merges — only keys you send change) and
   **`progress_photos`** (`read:photos` — metadata + `storage_path` /
   `thumb_path`; image bytes stay in private Storage, so sign the path with a
   same-account session — coach tokens get metadata only). Polling scale: the
   ≥60s events guidance is **per token** — a coach polling N clients at 60s
   each is fine.
9. **Consent can be trimmed — and diet plans carry groceries.** The Allow
   card in Jasper now has a **"Choose what to share"** picker: users can
   approve a SUBSET of the scopes a request asked for
   (`jasper_connect_respond` takes `p_scopes`; the approved set must be
   covered by the request — anything is coverable when it asked for `all`).
   Coach-grant invites can likewise be downgraded to **view-only** on the
   consent screen (`redeem_coach_grant_code(p_code, p_scope)` — downgrade
   only, never upgrade). So never assume a token carries what was requested:
   read `scopes` off the authorize/claim response or `GET /v1/me` and adapt.
   Also: every `diet_plans` read now ships **`payload.groceryList`** —
   `{ planName, itemCount, categories: [{ name, items: [{ name, quantity,
   usedInMeals }] }] }` — the exact grocery checklist Jasper renders in-app
   (categories: Proteins, Dairy & Eggs, Fruits & Vegetables, Grains & Bread,
   Pantry, Oils & Condiments, Beverages, Other). Render it next to the plan;
   don't re-derive it from ingredients.

### Appendix — the full resource surface

| Resource | Read scope | Write scope (POST) | Time field |
|---|---|---|---|
| `profile` | `read:profile` | — | — |
| `streaks` | `read:profile` | — | — |
| `achievements` | `read:profile` | — | `unlocked_at` |
| `workouts` | `read:workouts` | `write:workouts` | `performed_at` |
| `personal_records` | `read:workouts` | — | `achieved_at` |
| `programs` | `read:workouts` | `write:workouts` | `recorded_on` |
| `meals` | `read:nutrition` | `write:nutrition` | `logged_at` |
| `water` | `read:nutrition` | `write:nutrition` | `logged_at` |
| `diet_plans` | `read:nutrition` | `write:nutrition` | `recorded_on` |
|  ↳ `payload` carries `days[]` AND `groceryList` (the in-app checklist) | | | |
| `preferences` | `read:preferences` | `write:preferences` (merge) | — |
| `sleep` | `read:sleep` | — | `started_at` |
| `readiness` | `read:vitals` | — | `recorded_on` |
| `heart_rate` | `read:vitals` | — | `recorded_on` |
| `steps` | `read:vitals` | — | `recorded_on` |
| `energy` | `read:vitals` | — | `recorded_on` |
| `body` | `read:body` | `write:body` | `recorded_on` |
| `weight` | `read:body` | `write:body` (kg or pounds) | `measured_at` |
| `progress_photos` | `read:photos` | — (metadata only) | `recorded_on` |
| `bioage` | `read:bioage` | — (never writable) | `recorded_on` |
| `blood_panels` | `read:blood` | `write:blood` (merges by `drawn_on`) | `drawn_on` |
| `goals` | `read:goals` | — (read-only blob) | — |
| `goal_entries` | `read:goals` | `write:goals` | `recorded_on` |
| `shared_charts` | `read:charts` | — (post via `/v1/charts`) | `created_at` |
| `events` | `read:events` | — | `occurred_at` |
| `charts` *(write-only)* | — | `write:charts` | — |

All reads accept `?since=` (ISO 8601, resources with a time field), `?limit=`
(1–200, default 100); `events` also takes `?cursor=`. Writes upsert by
`client_id`. `DELETE /v1/<resource>?id=` works on every resource with a write
scope (charts: own posts only). The `all` scope covers every row above — with
one exception: on **coach** tokens it never covers `read:blood` /
`write:blood` (explicit scope required). Exact per-resource row keys are
published in `GET /v1/catalog` as `fields` / `write_fields`. Reads for
`bioage`, `readiness`, `sleep`, and `shared_charts` also carry the `look`
render spec (§5 → "Native looks").

---

Published on the marketing site for download (same pattern as the others):

- `https://www.thejasperapp.com/WHISPER_CONNECT.md`
- `https://www.thejasperapp.com/WHISPER_LINKING.md`
- `https://www.thejasperapp.com/WHISPER_BRIDGE.md`
- `https://www.thejasperapp.com/WHISPER_VOICE.md`
- `https://www.thejasperapp.com/WHISPER_DESIGN.md`
- `https://www.thejasperapp.com/WHISPER_RECIPES.md`
