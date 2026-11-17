import Foundation

// MARK: - Model

/// One coach-published template on Jasper's public plan marketplace
/// (Aug 17 2026 launch). Browse and preview are public — no auth at all;
/// the full `payload` (exactly plan_shapes) rides the detail read.
nonisolated struct JasperMarketTemplate: Identifiable {
    let id: String
    let kind: String            // "program" | "diet_plan"
    let title: String
    let summary: String?
    let goal: String?
    let coachUsername: String?
    let priceUSD: Double?
    let purchaseURL: String?
    let importCount: Int?
    let publishedAt: Date?
    /// Browse-level meta Jasper surfaces before the full payload
    /// (weeks / days_per_week for programs, kcal for diet plans…).
    let topLevel: [String: Any]
    /// Full plan_shapes payload — present on detail reads only.
    let payload: [String: Any]?

    var isProgram: Bool { kind.lowercased().contains("program") }
    var isFree: Bool { (priceUSD ?? 0) <= 0 }

    var kindLabel: String { isProgram ? "Program" : "Diet plan" }
    var kindSymbol: String { isProgram ? "figure.strengthtraining.traditional" : "fork.knife" }

    /// "12 weeks · 4 days/week" style meta line from `top_level`.
    var metaLine: String? {
        var parts: [String] = []
        if let weeks = JasperClientDashboard.intAny(topLevel["weeks"]) { parts.append("\(weeks) wk") }
        if let days = JasperClientDashboard.intAny(topLevel["days_per_week"] ?? topLevel["daysPerWeek"]) {
            parts.append("\(days) days/wk")
        }
        if let kcal = JasperClientDashboard.intAny(topLevel["kcal"] ?? topLevel["target_calories"] ?? topLevel["calories"]) {
            parts.append("\(kcal) kcal/day")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var priceLabel: String {
        guard let price = priceUSD, price > 0 else { return "Free" }
        return String(format: "$%.0f", price)
    }

    nonisolated static func parse(_ row: [String: Any]) -> JasperMarketTemplate? {
        guard let id = (row["id"] as? String) ?? (row["template_id"] as? String) else { return nil }
        let title = (row["title"] as? String) ?? (row["name"] as? String) ?? "Untitled plan"
        return JasperMarketTemplate(
            id: id,
            kind: (row["kind"] as? String) ?? "program",
            title: title,
            summary: row["summary"] as? String,
            goal: row["goal"] as? String,
            coachUsername: (row["coach_username"] as? String) ?? (row["coachUsername"] as? String),
            priceUSD: JasperClientDashboard.doubleAny(row["price_usd"]),
            purchaseURL: row["purchase_url"] as? String,
            importCount: JasperClientDashboard.intAny(row["import_count"] ?? row["imports"]),
            publishedAt: jasperConnectDate(row["published_at"] ?? row["created_at"] ?? row["updated_at"]),
            topLevel: (row["top_level"] as? [String: Any]) ?? [:],
            payload: row["payload"] as? [String: Any])
    }
}

// MARK: - Service

/// Jasper's public plan marketplace, per the Aug 17 2026 contract:
/// `GET /v1/marketplace` (public browse), `GET /v1/marketplace/<id>` (public
/// preview with the full plan_shapes payload), `POST /v1/marketplace`
/// (publish — Bearer is the coach's OWN Supabase session JWT, the same
/// Bearer as /v1/authorize; validated against plan_shapes at publish time),
/// `DELETE /v1/marketplace?id=` (unpublish), and
/// `POST /v1/marketplace/import { template_id }` on a client `jc_` token
/// (imports upsert by template id — importing twice never duplicates — and
/// carry coach attribution; the server rewrites payload.id/createdAt).
@MainActor
@Observable
final class JasperMarketplace {
    static let shared = JasperMarketplace()

    /// Last successful browse result (5-minute freshness — the marketplace
    /// is a catalog, not a live feed).
    private(set) var templates: [JasperMarketTemplate] = []
    private(set) var browsing = false
    private(set) var lastError: String?
    private(set) var fetchedAt: Date?

    @ObservationIgnored private var inFlight: Task<[JasperMarketTemplate], Never>?
    private let session = URLSession.shared

    private init() {}

    /// The signed-in coach's own listings, matched by Jasper attribution.
    var myListings: [JasperMarketTemplate] {
        guard let mine = ownUsername()?.lowercased(), !mine.isEmpty else { return [] }
        return templates.filter { $0.coachUsername?.lowercased() == mine }
    }

    func ownUsername() -> String? {
        JasperConnectClient.shared.connection?.username
            ?? LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
    }

    // MARK: Browse / preview (public — no auth)

    @discardableResult
    func browse(kind: String? = nil, query: String? = nil, force: Bool = false) async -> [JasperMarketTemplate] {
        // Only the unfiltered browse is cached — filtered reads pass through.
        let isBase = (kind == nil && (query ?? "").isEmpty)
        if isBase, !force, let at = fetchedAt, Date().timeIntervalSince(at) < 300, !templates.isEmpty {
            return templates
        }
        if isBase, let running = inFlight { return await running.value }
        let task = Task<[JasperMarketTemplate], Never> {
            await self.fetchList(kind: kind, query: query, cache: isBase)
        }
        if isBase { inFlight = task }
        let result = await task.value
        if isBase { inFlight = nil }
        return result
    }

    private func fetchList(kind: String?, query: String?, cache: Bool) async -> [JasperMarketTemplate] {
        browsing = true
        defer { browsing = false }
        var items: [URLQueryItem] = []
        if let kind, !kind.isEmpty { items.append(URLQueryItem(name: "kind", value: kind)) }
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        do {
            let data = try await request(path: "/v1/marketplace", query: items, method: "GET")
            let rows = Self.rows(from: data)
            let parsed = rows.compactMap(JasperMarketTemplate.parse)
            if cache {
                templates = parsed
                fetchedAt = Date()
            }
            lastError = nil
            print("[JasperMarket] browse kind=\(kind ?? "all") q=\(query ?? "") → \(parsed.count) templates")
            return parsed
        } catch {
            lastError = Self.friendly(error)
            print("[JasperMarket] browse failed: \(lastError ?? "?")")
            return cache ? templates : []
        }
    }

    /// Full template with the plan_shapes payload — public, no auth.
    func template(id: String) async -> JasperMarketTemplate? {
        do {
            let data = try await request(path: "/v1/marketplace/\(id)", method: "GET")
            guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            let row = (body["template"] as? [String: Any])
                ?? (body["data"] as? [String: Any])
                ?? body
            return JasperMarketTemplate.parse(row)
        } catch {
            lastError = Self.friendly(error)
            return nil
        }
    }

    // MARK: Publish / unpublish (coach session JWT — same Bearer as /v1/authorize)

    /// Publishes a plan_shapes-exact payload. Re-publishing the same title
    /// updates in place. Returns the template id when Jasper reports one.
    @discardableResult
    func publish(kind: String, title: String, summary: String, goal: String,
                 priceUSD: Double = 0, topLevel: [String: Any],
                 payload: [String: Any]) async throws -> String? {
        let jwt = try await JasperConnectConfig.sessionJWT()
        let body: [String: Any] = [
            "kind": kind,
            "title": title,
            "summary": summary,
            "goal": goal,
            "price_usd": priceUSD,
            "top_level": topLevel,
            "payload": payload,
        ]
        let data = try await request(path: "/v1/marketplace", method: "POST", payload: body, bearer: jwt)
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let id = (reply?["id"] as? String) ?? ((reply?["template"] as? [String: Any])?["id"] as? String)
        fetchedAt = nil   // listing changed — next browse refetches
        print("[JasperMarket] published \(kind) \"\(title)\" id=\(id ?? "?")")
        return id
    }

    func unpublish(id: String) async throws {
        let jwt = try await JasperConnectConfig.sessionJWT()
        _ = try await request(path: "/v1/marketplace",
                              query: [URLQueryItem(name: "id", value: id)],
                              method: "DELETE", bearer: jwt)
        templates.removeAll { $0.id == id }
        fetchedAt = nil
        print("[JasperMarket] unpublished \(id)")
    }

    // MARK: Import

    /// Into the signed-in user's OWN Jasper — their own jc_ token.
    func importForSelf(templateID: String) async throws {
        _ = try await JasperConnectClient.shared.dataRequest(
            path: "/v1/marketplace/import", method: "POST",
            payload: ["template_id": templateID])
        print("[JasperMarket] imported \(templateID) into own Jasper")
    }

    // MARK: Plumbing

    nonisolated private static func rows(from data: Data) -> [[String: Any]] {
        let any = try? JSONSerialization.jsonObject(with: data)
        if let arr = any as? [[String: Any]] { return arr }
        if let dict = any as? [String: Any] {
            for key in ["data", "templates", "rows", "items"] {
                if let arr = dict[key] as? [[String: Any]] { return arr }
            }
        }
        return []
    }

    /// Bare marketplace request against the same API base as every other
    /// Connect call. `bearer` nil ⇒ genuinely public (browse/preview).
    private func request(path: String, query: [URLQueryItem] = [], method: String,
                         payload: [String: Any]? = nil, bearer: String? = nil) async throws -> Data {
        guard var components = URLComponents(url: JasperConnectConfig.apiBase,
                                             resolvingAgainstBaseURL: false) else {
            throw JasperConnectError.server("Bad Jasper Connect base URL.")
        }
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw JasperConnectError.server("Couldn't build the marketplace URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw JasperConnectError.notSignedIn }
        if !(200..<300).contains(status) {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (body?["error"] as? String) ?? "Marketplace error (\(status))."
            let hint = body?["hint"] as? String
            throw JasperConnectError.server([message, hint].compactMap { $0 }.joined(separator: " "))
        }
        return data
    }

    nonisolated static func friendly(_ error: Error) -> String {
        if let known = error as? JasperConnectError {
            return known.errorDescription ?? "Something went wrong."
        }
        return (error as NSError).domain == NSURLErrorDomain
            ? "You're offline — try again when you have a connection."
            : error.localizedDescription
    }
}
