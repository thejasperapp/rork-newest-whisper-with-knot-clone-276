import Foundation
import Supabase

// MARK: - Backend URL

/// The Cloudflare functions backend that owns the Stripe integration.
/// Mirrors the web app's `BACKEND_URL` — must point to the same deployment.
enum WhisperBillingBackend {
    static let url: String = {
        let configured = Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL
        if !configured.isEmpty { return configured }
        // PERMANENT project alias — always tracks the newest functions
        // deploy. Per-deploy hosts (…-g6gawm9-…, …-pvganrz-…) freeze the
        // code AND the env they shipped with forever, so never hardcode
        // one again. Verify with GET /ping → { version, stripeKeyMode }.
        return "https://mdt742q5xnsko5i7owb0v-backend.rork.app"
    }()

    /// Ordered backend candidates. Voice tokens and Jasper narration walk
    /// this list so a stale configured URL (an env pointing at a superseded
    /// deploy that lacks the newer AI routes) can never silently kill
    /// Jasper's live voice or the deck walkthrough again.
    static let hosts: [String] = {
        var list: [String] = []
        let configured = Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty { list.append(configured) }
        let stable = "https://mdt742q5xnsko5i7owb0v-backend.rork.app"
        if !list.contains(stable) { list.append(stable) }
        // Per-deploy hosts churn on every deploy and freeze their code +
        // env forever — keep the newest first; moneyURL() below probes
        // them and always picks the freshest LIVE deploy.
        // r63 carries /link/preview + the AI routes.
        let latest = "https://whisper-008-clone-clone-clone-o4g0jln-backend.rork.app"
        if !list.contains(latest) { list.append(latest) }
        let newest = "https://whisper-008-clone-clone-clone-bg7wah6-backend.rork.app"
        if !list.contains(newest) { list.append(newest) }
        let current = "https://whisper-008-clone-clone-clone-vru24ih-backend.rork.app"
        if !list.contains(current) { list.append(current) }
        // Last-known-good per-deploy host kept as a network-level fallback
        // for the AI routes (serves frozen r38 code).
        let legacy = "https://whisper-008-clone-clone-clone-g6gawm9-backend.rork.app"
        if !list.contains(legacy) { list.append(legacy) }
        return list
    }()

    /// The public web app origin used for every shareable link (profiles,
    /// coach hire pages, creator invite links). Always the production
    /// domain — preview hosts rotate between deploys and links would rot.
    static let webOrigin: String = "https://mydailywhisper.com"

    // MARK: Money-path resolution

    private static var resolvedMoneyURL: String?

    /// The backend for MONEY calls (checkout, earnings, refunds). Probes
    /// every candidate's /ping and prefers the NEWEST deploy reporting
    /// LIVE Stripe keys — the permanent alias can lag deploys with a stale
    /// env, and per-deploy hosts freeze old code forever, so neither is
    /// trustworthy alone. Mirrors the web app's resolveBackend(). Cached
    /// for the app session.
    static func moneyURL() async -> String {
        if let cached = resolvedMoneyURL { return cached }
        var probes: [WhisperBackendProbe] = []
        await withTaskGroup(of: WhisperBackendProbe?.self) { group in
            for host in hosts {
                group.addTask { await probeHost(host) }
            }
            for await result in group {
                if let result { probes.append(result) }
            }
        }
        let live = probes.filter(\.live).max { $0.version < $1.version }
        let reachable = probes.max { $0.version < $1.version }
        let resolved = live?.url ?? reachable?.url ?? url
        resolvedMoneyURL = resolved
        return resolved
    }

    /// Reads /ping on one candidate — 4s budget, tolerant of any failure.
    private nonisolated static func probeHost(_ host: String) async -> WhisperBackendProbe? {
        guard let pingURL = URL(string: "\(host)/ping") else { return nil }
        var request = URLRequest(url: pingURL)
        request.timeoutInterval = 4
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let live = (json["stripeKeyMode"] as? String) == "live"
        let versionText = (json["version"] as? String) ?? ""
        let version = Int(versionText.filter(\.isNumber)) ?? 0
        return WhisperBackendProbe(url: host, live: live, version: version)
    }
}

/// One /ping probe result — used to pick the freshest live backend.
nonisolated struct WhisperBackendProbe: Sendable {
    let url: String
    let live: Bool
    let version: Int
}

// MARK: - Plan definitions

enum WhisperOnePlan: String, Sendable {
    case monthly = "one-monthly"
    case annual = "one-annual"

    var displayName: String {
        switch self {
        case .monthly: return "Whisper One · Monthly"
        case .annual:  return "Whisper One · Annual"
        }
    }

    var priceText: String {
        switch self {
        case .monthly: return "$14.99"
        case .annual:  return "$119.99"
        }
    }

    var intervalText: String {
        switch self {
        case .monthly: return "/month"
        case .annual:  return "/year"
        }
    }

    var blurb: String {
        switch self {
        case .monthly: return "Cancel anytime"
        case .annual:  return "Save 33% compared with monthly"
        }
    }
}

enum WhisperBadgeRole: String, Sendable, CaseIterable {
    case coach
    case athlete
    case verified

    var planID: String { "\(rawValue)-annual" }

    var displayName: String {
        switch self {
        case .coach:    return "Verified Coach"
        case .athlete:  return "Verified Athlete"
        case .verified: return "Verified"
        }
    }

    var priceText: String {
        switch self {
        case .coach:    return "$249.99"
        case .athlete:  return "$99.99"
        case .verified: return "$99.99"
        }
    }

    var blurb: String {
        switch self {
        case .coach:    return "Billed once per year · Coach profile role · unlimited clients · paywalled coaching"
        case .athlete:  return "Billed once per year · athlete label · verified stat sheet · reach perks"
        case .verified: return "Billed once per year · Creator profile role · algorithm boost · priority push"
        }
    }
}

// MARK: - Response types

nonisolated struct WhisperCheckoutResponse: Decodable, Sendable {
    let url: String?
    let clientSecret: String?
    let publishableKey: String?
    let error: String?
}

nonisolated struct WhisperConnectStatus: Decodable, Sendable {
    let connected: Bool
    let chargesEnabled: Bool?
    let payoutsEnabled: Bool?
    let detailsSubmitted: Bool?
}

nonisolated struct WhisperCoachEarnings: Decodable, Sendable {
    let connected: Bool
    let payoutsEnabled: Bool
    let chargesEnabled: Bool
    let totalEarnedCents: Int
    let availableCents: Int
    let pendingCents: Int
    let payments: [WhisperCoachPaymentRow]
}

nonisolated struct WhisperCoachPaymentRow: Decodable, Sendable, Identifiable {
    let gross_cents: Int
    let fee_cents: Int
    let net_cents: Int
    let client_email: String?
    let description: String?
    let created_at: String
    nonisolated var id: String { created_at + String(net_cents) }
}

nonisolated struct WhisperCoachRate: Decodable, Sendable {
    let monthlyPriceCents: Int?
    let active: Bool
    let acceptingPayments: Bool
    let username: String?
    let displayName: String?
    /// Published plan tiers (up to 3). Empty/nil → single-rate coach.
    let tiers: [WhisperCoachTier]?
}

/// One published coach plan — mirrors the web hire page's tier cards.
nonisolated struct WhisperCoachTier: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let tagline: String?
    let monthlyPriceCents: Int
    let perks: [String]
}

/// The user's FULL Stripe standing — status, requirements, balance, bank on
/// file, payout schedule, payouts, and incoming transfers — rendered inside
/// Whisper so nobody has to hop to the Stripe dashboard. Mirrors the web
/// earnings page's overview card.
nonisolated struct WhisperStripeOverview: Decodable, Sendable {
    let connected: Bool
    let chargesEnabled: Bool?
    let payoutsEnabled: Bool?
    let detailsSubmitted: Bool?
    let requirementsDue: [String]?
    let disabledReason: String?
    let balance: Balance?
    let bank: Bank?
    let payoutSchedule: Schedule?
    let payouts: [PayoutRow]?
    let transfers: [TransferRow]?

    nonisolated struct Balance: Decodable, Sendable {
        let availableCents: Int
        let pendingCents: Int
    }

    nonisolated struct Bank: Decodable, Sendable {
        let bankName: String
        let last4: String
        let currency: String
    }

    nonisolated struct Schedule: Decodable, Sendable {
        let interval: String
        let delayDays: Int
    }

    nonisolated struct PayoutRow: Decodable, Sendable, Identifiable {
        let amountCents: Int
        let status: String
        let arrivalDate: String?
        let createdAt: String?
        nonisolated var id: String {
            (createdAt ?? arrivalDate ?? "") + status + String(amountCents)
        }
    }

    nonisolated struct TransferRow: Decodable, Sendable, Identifiable {
        let amountCents: Int
        let description: String
        let createdAt: String?
        nonisolated var id: String {
            (createdAt ?? "") + description + String(amountCents)
        }
    }
}

/// The signed-in creator's WPP (Whisper Paid Partners) standing — the
/// ad-revenue share. 50% of real ad spend funds the monthly creator pool;
/// a creator's month = min(views × tier RPM, view-share of the pool).
nonisolated struct WhisperWppSummary: Decodable, Sendable {
    let eligible: Bool
    let tierId: String?
    let tierLabel: String?
    let rpmCents: Int
    let followers: Int
    let monthViews: Int
    let allTimeViews: Int
    let accruedCents: Int
    let monthEstimatedCents: Int
    let poolMonthCents: Int
    let monthRevenueCents: Int
    let cashedOutCents: Int
    let availableCents: Int
    let connected: Bool
    let payoutsReady: Bool
    let nextTierLabel: String?
    let nextTierFollowers: Int?
}

nonisolated struct WhisperHireStatus: Decodable, Sendable {
    let requiresPayment: Bool
    let priceCents: Int?
    let paid: Bool
}

nonisolated struct WhisperProgramAccess: Sendable {
    let purchased: Bool
    let owner: Bool
    let priceCents: Int?
    let coachReady: Bool
}

nonisolated struct WhisperCoachSubscription: Decodable, Sendable, Identifiable {
    let id: String
    let coachUserId: String?
    let coachUsername: String?
    let priceCents: Int?
    let status: String
    let cancelAtPeriodEnd: Bool
    let currentPeriodEnd: String?
}

nonisolated struct WhisperPayoutResult: Decodable, Sendable {
    let ok: Bool?
    let amountCents: Int?
    let error: String?
}

// MARK: - Billing service

/// Thin client over the project's Cloudflare functions backend, which owns
/// the Stripe integration. The iOS app never touches Stripe keys directly;
/// it asks the backend for a hosted Checkout URL (opened via
/// ASWebAuthenticationSession) or calls authenticated endpoints with the
/// user's Supabase JWT.
@MainActor
@Observable
final class WhisperBillingService {
    static let shared = WhisperBillingService()

    private let client = SupabaseService.shared.client

    var lastError: String?
    var isProcessingCheckout: Bool = false

    private init() {}

    // MARK: - Auth helpers

    /// Returns the current Supabase access token for authenticated backend calls.
    private func accessToken() async throws -> String {
        let session = try await client.auth.session
        return session.accessToken
    }

    /// The current user's auth UUID (lowercased to match Postgres).
    private var currentUserID: String {
        AccountStorage.currentUserID.lowercased()
    }

    /// The current user's email (if available from the Supabase session).
    private var currentUserEmail: String? {
        client.auth.currentUser?.email
    }

    // MARK: - Generic request

    /// Makes an authenticated JSON request to the backend. Throws a
    /// user-friendly Error on failure.
    private func request(
        path: String,
        method: String = "GET",
        body: Encodable? = nil,
        requireAuth: Bool = true
    ) async throws -> [String: Any] {
        let owner = currentUserID
        let generation = AccountStorage.generation
        let base = await WhisperBillingBackend.moneyURL()
        guard generation == AccountStorage.generation, owner == currentUserID else { throw CancellationError() }
        guard let url = URL(string: "\(base)\(path)") else {
            throw WhisperBillingError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requireAuth {
            let token = try await accessToken()
            guard generation == AccountStorage.generation, owner == currentUserID,
                  client.auth.currentUser?.id.uuidString.lowercased() == owner else { throw CancellationError() }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperBillingError.networkError
        }
        guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUserID else { throw CancellationError() }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WhisperBillingError.networkError
        }
        if !(200...299).contains(httpResponse.statusCode) {
            let code = (json["error"] as? String) ?? ""
            throw WhisperBillingError.backendError(code: code, status: httpResponse.statusCode)
        }
        return json
    }

    // MARK: - Whisper One checkout

    /// Starts a hosted Stripe Checkout for a Whisper One plan. Returns a URL
    /// that should be opened in ASWebAuthenticationSession (so the callback
    /// returns to the app after payment).
    func startOneCheckout(plan: WhisperOnePlan) async throws -> URL {
        isProcessingCheckout = true
        defer { isProcessingCheckout = false }

        let body = WhisperCheckoutBody(
            plan: plan.rawValue,
            // Success/cancel URLs must land on the WEB app — its success page
            // runs fallback fulfillment. The backend host only serves JSON.
            origin: WhisperBillingBackend.webOrigin,
            userId: currentUserID,
            email: currentUserEmail ?? ""
        )
        let json = try await request(
            path: "/stripe/checkout",
            method: "POST",
            body: body
        )
        guard let urlString = json["url"] as? String, let url = URL(string: urlString) else {
            let error = (json["error"] as? String) ?? ""
            throw WhisperBillingError.checkoutFailed(error)
        }
        return url
    }

    // MARK: - Badge activation checkout

    /// Starts a hosted Stripe Checkout for a verified-badge plan (coach,
    /// athlete, or verified). The user must have an approved application
    /// before the backend will issue a session.
    func startBadgeCheckout(role: WhisperBadgeRole) async throws -> URL {
        isProcessingCheckout = true
        defer { isProcessingCheckout = false }

        let body = WhisperCheckoutBody(
            plan: role.planID,
            origin: WhisperBillingBackend.webOrigin,
            userId: currentUserID,
            email: currentUserEmail ?? ""
        )
        let json = try await request(
            path: "/stripe/checkout",
            method: "POST",
            body: body
        )
        guard let urlString = json["url"] as? String, let url = URL(string: urlString) else {
            let error = (json["error"] as? String) ?? ""
            throw WhisperBillingError.checkoutFailed(error)
        }
        return url
    }

    // MARK: - Coach Connect (bank linking)

    /// Fetches the coach's Stripe Connect onboarding status.
    func fetchConnectStatus() async throws -> WhisperConnectStatus {
        let json = try await request(path: "/coach/connect/status")
        return WhisperConnectStatus(
            connected: (json["connected"] as? Bool) ?? false,
            chargesEnabled: json["chargesEnabled"] as? Bool,
            payoutsEnabled: json["payoutsEnabled"] as? Bool,
            detailsSubmitted: json["detailsSubmitted"] as? Bool
        )
    }

    /// Returns a hosted Stripe onboarding URL for the coach to link their
    /// bank account. Opens in ASWebAuthenticationSession.
    func startConnectOnboarding() async throws -> URL {
        struct OriginBody: Encodable { let origin: String }
        let json = try await request(
            path: "/coach/connect/onboard",
            method: "POST",
            body: OriginBody(origin: WhisperBillingBackend.webOrigin)
        )
        guard let urlString = json["url"] as? String, let url = URL(string: urlString) else {
            throw WhisperBillingError.backendError(code: "stripe_error", status: 502)
        }
        return url
    }

    /// Opens the Stripe Express dashboard for the coach to manage payouts.
    func openStripeDashboard() async throws -> URL {
        let json = try await request(
            path: "/coach/connect/dashboard",
            method: "POST",
            body: EmptyBody()
        )
        guard let urlString = json["url"] as? String, let url = URL(string: urlString) else {
            throw WhisperBillingError.backendError(code: "stripe_error", status: 502)
        }
        return url
    }

    // MARK: - Coach pricing

    /// Sets the coach's monthly rate.
    func saveCoachRate(monthlyPriceCents: Int) async throws {
        struct PricingBody: Encodable {
            let monthlyPriceCents: Int
            let active: Bool
        }
        _ = try await request(
            path: "/coach/pricing",
            method: "POST",
            body: PricingBody(monthlyPriceCents: monthlyPriceCents, active: true)
        )
    }

    /// Fetches the public rate card for a coach (no auth required).
    func fetchCoachRate(coachUserID: String) async throws -> WhisperCoachRate {
        let encoded = coachUserID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? coachUserID
        let base = await WhisperBillingBackend.moneyURL()
        guard let url = URL(string: "\(base)/coach/pricing?userId=\(encoded)") else {
            throw WhisperBillingError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(WhisperCoachRate.self, from: data)
        return decoded
    }

    // MARK: - Stripe overview (in-app, no dashboard hop)

    /// Full Stripe standing for the signed-in user — status, requirements,
    /// live balance at Stripe, bank on file, payouts, and transfers.
    func fetchStripeOverview() async throws -> WhisperStripeOverview {
        let json = try await request(path: "/coach/stripe/overview")
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(WhisperStripeOverview.self, from: data)
    }

    // MARK: - WPP (Whisper Paid Partners)

    /// The signed-in creator's WPP standing — tier, views, estimate, pool,
    /// and cashable balance.
    func fetchWppSummary() async throws -> WhisperWppSummary {
        let json = try await request(path: "/wpp/summary")
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(WhisperWppSummary.self, from: data)
    }

    /// Cashes out the creator's finalized WPP balance through the same
    /// Stripe rail coaches use. Returns the amount and whether the onward
    /// bank push started.
    func wppCashOut() async throws -> (amountCents: Int, sentToBank: Bool) {
        let json = try await request(
            path: "/wpp/cashout",
            method: "POST",
            body: EmptyBody()
        )
        return (
            (json["amountCents"] as? Int) ?? 0,
            (json["sentToBank"] as? Bool) ?? false
        )
    }

    // MARK: - Coach earnings + payout

    func fetchCoachEarnings() async throws -> WhisperCoachEarnings {
        let json = try await request(path: "/coach/earnings")

        let payments: [WhisperCoachPaymentRow] = {
            guard let arr = json["payments"] as? [[String: Any]] else { return [] }
            return arr.compactMap { dict in
                guard let data = try? JSONSerialization.data(withJSONObject: dict),
                      let row = try? JSONDecoder().decode(WhisperCoachPaymentRow.self, from: data) else {
                    return nil
                }
                return row
            }
        }()

        return WhisperCoachEarnings(
            connected: (json["connected"] as? Bool) ?? false,
            payoutsEnabled: (json["payoutsEnabled"] as? Bool) ?? false,
            chargesEnabled: (json["chargesEnabled"] as? Bool) ?? false,
            totalEarnedCents: (json["totalEarnedCents"] as? Int) ?? 0,
            availableCents: (json["availableCents"] as? Int) ?? 0,
            pendingCents: (json["pendingCents"] as? Int) ?? 0,
            payments: payments
        )
    }

    /// Cashes out the full available balance to the coach's linked bank.
    func cashOut() async throws -> Int {
        let json = try await request(
            path: "/coach/payout",
            method: "POST",
            body: EmptyBody()
        )
        if let error = json["error"] as? String, !error.isEmpty {
            throw WhisperBillingError.backendError(code: error, status: 400)
        }
        return (json["amountCents"] as? Int) ?? 0
    }

    // MARK: - Coach hire (client side)

    /// Checks whether the signed-in client needs to pay a coach.
    func fetchHireStatus(coachUserID: String) async throws -> WhisperHireStatus {
        let encoded = coachUserID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? coachUserID
        let json = try await request(path: "/coach/hire-status?coachUserId=\(encoded)")
        return WhisperHireStatus(
            requiresPayment: (json["requiresPayment"] as? Bool) ?? false,
            priceCents: json["priceCents"] as? Int,
            paid: (json["paid"] as? Bool) ?? false
        )
    }

    /// Starts a hosted Stripe Checkout for hiring a coach (optionally on a
    /// specific published plan tier). Returns a URL to open in
    /// ASWebAuthenticationSession.
    func startHireCheckout(coachUserID: String, tierId: String? = nil) async throws -> URL {
        isProcessingCheckout = true
        defer { isProcessingCheckout = false }

        struct HireBody: Encodable {
            let coachUserId: String
            let tierId: String
            let userId: String
            let email: String
            let origin: String
            let cancelPath: String
        }
        let json = try await request(
            path: "/coach/hire-checkout",
            method: "POST",
            body: HireBody(
                coachUserId: coachUserID,
                tierId: tierId ?? "",
                userId: currentUserID,
                email: currentUserEmail ?? "",
                origin: WhisperBillingBackend.webOrigin,
                cancelPath: "/coach/hire"
            )
        )
        guard let urlString = json["url"] as? String, let url = URL(string: urlString) else {
            let error = (json["error"] as? String) ?? ""
            throw WhisperBillingError.checkoutFailed(error)
        }
        return url
    }

    // MARK: - Program purchases (client side)

    /// Whether the signed-in user can open a paid program.
    func fetchProgramAccess(programID: String) async throws -> WhisperProgramAccess {
        let encoded = programID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? programID
        let json = try await request(path: "/coach/program-access?programId=\(encoded)")
        return WhisperProgramAccess(
            purchased: (json["purchased"] as? Bool) ?? false,
            owner: (json["owner"] as? Bool) ?? false,
            priceCents: json["priceCents"] as? Int,
            coachReady: (json["coachReady"] as? Bool) ?? true
        )
    }

    /// Starts a hosted one-time Stripe Checkout for a training program.
    /// Returns nil when the buyer already owns it (nothing to pay).
    func startProgramCheckout(programID: String) async throws -> URL? {
        isProcessingCheckout = true
        defer { isProcessingCheckout = false }

        struct ProgramBody: Encodable {
            let programId: String
            let userId: String
            let email: String
            let origin: String
            let cancelPath: String
        }
        let json = try await request(
            path: "/coach/program-checkout",
            method: "POST",
            body: ProgramBody(
                programId: programID,
                userId: currentUserID,
                email: currentUserEmail ?? "",
                origin: WhisperBillingBackend.webOrigin,
                cancelPath: "/messages"
            )
        )
        if (json["alreadyPurchased"] as? Bool) == true { return nil }
        guard let urlString = json["url"] as? String, let url = URL(string: urlString) else {
            let error = (json["error"] as? String) ?? ""
            throw WhisperBillingError.checkoutFailed(error)
        }
        return url
    }

    /// Fetches the signed-in client's active coaching subscriptions.
    func fetchMyCoachSubscriptions() async throws -> [WhisperCoachSubscription] {
        let json = try await request(path: "/coach/my-hires")
        guard let arr = json["subscriptions"] as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let sub = try? JSONDecoder().decode(WhisperCoachSubscription.self, from: data) else {
                return nil
            }
            return sub
        }
    }

    /// Cancels a coaching subscription at the end of the current paid month.
    func cancelCoachSubscription(subscriptionID: String) async throws {
        struct CancelBody: Encodable { let subscriptionId: String }
        _ = try await request(
            path: "/coach/hire-cancel",
            method: "POST",
            body: CancelBody(subscriptionId: subscriptionID)
        )
    }

    // MARK: - Admin: featured profiles

    /// Admin: fetch all featured profiles (including drafts).
    func adminFetchFeatured() async throws -> [[String: Any]] {
        let json = try await request(path: "/admin/featured")
        guard let profiles = json["profiles"] as? [[String: Any]] else { return [] }
        return profiles
    }

    /// Admin: create or update a featured profile.
    func adminUpsertFeatured(_ input: [String: Any]) async throws -> String {
        let bodyData = try JSONSerialization.data(withJSONObject: input)
        let base = await WhisperBillingBackend.moneyURL()
        guard let url = URL(string: "\(base)/admin/featured/upsert") else {
            throw WhisperBillingError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = try await accessToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WhisperBillingError.networkError
        }
        if !(200...299).contains(httpResponse.statusCode) {
            let code = (result["error"] as? String) ?? ""
            throw WhisperBillingError.backendError(code: code, status: httpResponse.statusCode)
        }
        return (result["id"] as? String) ?? ""
    }

    /// Admin: delete a featured profile.
    func adminDeleteFeatured(id: String) async throws {
        struct DeleteBody: Encodable { let id: String }
        _ = try await request(
            path: "/admin/featured/delete",
            method: "POST",
            body: DeleteBody(id: id)
        )
    }

    // MARK: - Admin: articles

    /// Admin: fetch all articles including drafts.
    func adminFetchArticles() async throws -> [[String: Any]] {
        let json = try await request(path: "/admin/articles")
        guard let articles = json["articles"] as? [[String: Any]] else { return [] }
        return articles
    }

    /// Admin: create or update an article.
    func adminUpsertArticle(_ input: [String: Any]) async throws -> String {
        let bodyData = try JSONSerialization.data(withJSONObject: input)
        let base = await WhisperBillingBackend.moneyURL()
        guard let url = URL(string: "\(base)/admin/articles/upsert") else {
            throw WhisperBillingError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = try await accessToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WhisperBillingError.networkError
        }
        if !(200...299).contains(httpResponse.statusCode) {
            let code = (result["error"] as? String) ?? ""
            throw WhisperBillingError.backendError(code: code, status: httpResponse.statusCode)
        }
        return (result["id"] as? String) ?? ""
    }

    /// Admin: delete an article.
    func adminDeleteArticle(id: String) async throws {
        struct DeleteBody: Encodable { let id: String }
        _ = try await request(
            path: "/admin/articles/delete",
            method: "POST",
            body: DeleteBody(id: id)
        )
    }

    /// Admin: seed starter articles.
    func adminSeedArticles() async throws -> Int {
        let json = try await request(path: "/admin/articles/seed", method: "POST", body: EmptyBody())
        return (json["inserted"] as? Int) ?? 0
    }

    // MARK: - Author: articles

    /// Badge holder: fetch their own articles (drafts included).
    func authorFetchArticles() async throws -> [[String: Any]] {
        let json = try await request(path: "/author/articles")
        guard let articles = json["articles"] as? [[String: Any]] else { return [] }
        return articles
    }

    /// Badge holder: create or update their own article.
    func authorUpsertArticle(_ input: [String: Any]) async throws -> String {
        let bodyData = try JSONSerialization.data(withJSONObject: input)
        let base = await WhisperBillingBackend.moneyURL()
        guard let url = URL(string: "\(base)/author/articles/upsert") else {
            throw WhisperBillingError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = try await accessToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WhisperBillingError.networkError
        }
        if !(200...299).contains(httpResponse.statusCode) {
            let code = (result["error"] as? String) ?? ""
            throw WhisperBillingError.backendError(code: code, status: httpResponse.statusCode)
        }
        return (result["id"] as? String) ?? ""
    }

    /// Badge holder: delete their own article.
    func authorDeleteArticle(id: String) async throws {
        struct DeleteBody: Encodable { let id: String }
        _ = try await request(
            path: "/author/articles/delete",
            method: "POST",
            body: DeleteBody(id: id)
        )
    }

    // MARK: - Admin: team

    /// Admin: fetch the team roster.
    func adminFetchTeam() async throws -> [[String: Any]] {
        let json = try await request(path: "/admin/team")
        guard let members = json["members"] as? [[String: Any]] else { return [] }
        return members
    }

    /// Admin: add or re-role a team member.
    func adminUpsertTeamMember(identifier: String, role: String) async throws {
        struct TeamBody: Encodable {
            let identifier: String
            let role: String
        }
        _ = try await request(
            path: "/admin/team/upsert",
            method: "POST",
            body: TeamBody(identifier: identifier, role: role)
        )
    }

    /// Admin: remove a team member.
    func adminRemoveTeamMember(userID: String) async throws {
        struct RemoveBody: Encodable { let userId: String }
        _ = try await request(
            path: "/admin/team/remove",
            method: "POST",
            body: RemoveBody(userId: userID)
        )
    }

    // MARK: - Support contact

    /// Sends a contact/support form submission.
    func submitContact(name: String, email: String, message: String) async throws {
        struct ContactBody: Encodable {
            let name: String
            let email: String
            let message: String
        }
        _ = try await request(
            path: "/support/contact",
            method: "POST",
            body: ContactBody(name: name, email: email, message: message),
            requireAuth: false
        )
    }

    // MARK: - Helpers

    /// Formats cents as a currency string.
    nonisolated static func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }
}

// MARK: - Error types

nonisolated enum WhisperBillingError: LocalizedError {
    case invalidURL
    case networkError
    case checkoutFailed(String)
    case backendError(code: String, status: Int)

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Couldn't reach the payment service."
        case .networkError:
            return "Couldn't reach the payment service. Please try again."
        case .checkoutFailed(let code):
            return Self.friendlyMessage(for: code)
        case .backendError(let code, _):
            return Self.friendlyMessage(for: code)
        }
    }

    nonisolated static func friendlyMessage(for code: String) -> String {
        switch code {
        case "billing_not_configured":
            return "Payments are almost live — Stripe isn't connected yet."
        case "sign_in_required":
            return "Please sign in or create an account first."
        case "not_approved":
            return "This badge unlocks after your application is approved."
        case "not_a_coach":
            return "Only approved coaches can use coach payouts."
        case "not_payout_eligible":
            return "Payouts unlock once you're a verified coach, athlete, or creator (or have an active sponsorship)."
        case "already_applied":
            return "You already have an application with this brand."
        case "age_requirement":
            return "You don't meet this brand's minimum age requirement."
        case "brand_not_found":
            return "This brand profile isn't available."
        case "deal_not_active":
            return "This sponsorship deal isn't active."
        case "already_decided":
            return "This application has already been decided."
        case "company_name_required":
            return "Enter your company name first."
        case "not_connected":
            return "Link your bank account first."
        case "not_eligible":
            return "WPP opens at 1,000 followers — keep growing!"
        case "below_minimum":
            return "You need at least $10 in closed months to cash out."
        case "payouts_not_ready":
            return "Finish linking your bank first — then cash outs are one tap."
        case "tier_not_found":
            return "That plan isn't available anymore — pick another."
        case "insufficient_balance":
            return "Your available balance is under $1 — nothing to cash out yet."
        case "invalid_price":
            return "Enter a monthly rate between $5 and $2,000."
        case "connect_not_enabled":
            return "Coach payouts aren't live yet — Stripe Connect needs to be enabled."
        case "coach_not_priced":
            return "This coach hasn't set their rate yet."
        case "coach_not_ready":
            return "This coach isn't accepting payments yet."
        case "cannot_hire_self":
            return "You can't hire yourself."
        case "program_not_found":
            return "This program no longer exists."
        case "program_not_priced":
            return "This program isn't for sale."
        case "cannot_buy_own_program":
            return "This is your own program."
        case "forbidden":
            return "Your account doesn't have permission for this."
        case "stripe_error":
            return "Something went wrong with the payment provider. Please try again."
        default:
            return "Something went wrong. Please try again."
        }
    }
}

// MARK: - Wire types

nonisolated struct WhisperCheckoutBody: Encodable, Sendable {
    let plan: String
    let origin: String
    let userId: String
    let email: String
}

nonisolated struct EmptyBody: Encodable {}
