import Foundation
import Supabase
import UIKit

// MARK: - Models

/// How a sponsorship is paid out.
nonisolated enum WhisperSponsorBasis: String, Sendable, CaseIterable, Identifiable {
    case perPost = "per_post"
    case perMonth = "per_month"
    case perYear = "per_year"

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .perPost:  return "Per post"
        case .perMonth: return "Per month"
        case .perYear:  return "Per year"
        }
    }

    nonisolated var shortLabel: String {
        switch self {
        case .perPost:  return "/post"
        case .perMonth: return "/mo"
        case .perYear:  return "/yr"
        }
    }
}

/// A brand account profile — company info, sponsorship requirements, and
/// transparent typical pay.
nonisolated struct WhisperBrandProfile: Sendable, Identifiable, Hashable {
    let userId: String
    let companyName: String
    let username: String?
    let website: String?
    let industry: String?
    let about: String?
    let logoUrl: String?
    let instagram: String?
    let emberVerified: Bool
    let emberScore: Int?
    let emberSummary: String?
    let amenities: [String]
    let minFollowers: Int
    let minAge: Int
    let minPosts: Int
    let payBasis: String
    let typicalPayMinCents: Int?
    let typicalPayMaxCents: Int?
    let paymentTerms: String?
    let published: Bool
    var coverUrl: String? = nil
    var mediaUrls: [String] = []
    var videoUrl: String? = nil

    nonisolated var id: String { userId }

    nonisolated var basisEnum: WhisperSponsorBasis {
        WhisperSponsorBasis(rawValue: payBasis) ?? .perPost
    }

    /// "Typically pays $200–$500 /post" transparency line, or nil.
    nonisolated var typicalPayText: String? {
        let minC = typicalPayMinCents
        let maxC = typicalPayMaxCents
        guard minC != nil || maxC != nil else { return nil }
        let fmt = { (c: Int) in WhisperBillingService.formatCents(c) }
        if let lo = minC, let hi = maxC, hi > lo {
            return "\(fmt(lo))–\(fmt(hi)) \(basisEnum.shortLabel)"
        }
        if let lo = minC ?? maxC {
            return "~\(fmt(lo)) \(basisEnum.shortLabel)"
        }
        return nil
    }

    nonisolated static func from(_ dict: [String: Any]) -> WhisperBrandProfile? {
        guard let userId = dict["user_id"] as? String,
              let companyName = dict["company_name"] as? String else { return nil }
        return WhisperBrandProfile(
            userId: userId,
            companyName: companyName,
            username: dict["username"] as? String,
            website: dict["website"] as? String,
            industry: dict["industry"] as? String,
            about: dict["about"] as? String,
            logoUrl: dict["logo_url"] as? String,
            instagram: dict["instagram"] as? String,
            emberVerified: (dict["ember_verified"] as? Bool) ?? false,
            emberScore: dict["ember_score"] as? Int,
            emberSummary: dict["ember_summary"] as? String,
            amenities: (dict["amenities"] as? [String]) ?? [],
            minFollowers: (dict["min_followers"] as? Int) ?? 0,
            minAge: (dict["min_age"] as? Int) ?? 18,
            minPosts: (dict["min_posts"] as? Int) ?? 0,
            payBasis: (dict["pay_basis"] as? String) ?? "per_post",
            typicalPayMinCents: dict["typical_pay_min_cents"] as? Int,
            typicalPayMaxCents: dict["typical_pay_max_cents"] as? Int,
            paymentTerms: dict["payment_terms"] as? String,
            published: (dict["published"] as? Bool) ?? true,
            coverUrl: dict["cover_url"] as? String,
            mediaUrls: (dict["media_urls"] as? [String]) ?? [],
            videoUrl: dict["video_url"] as? String
        )
    }
}

/// A creator's sponsorship application to a brand.
nonisolated struct WhisperSponsorApplication: Sendable, Identifiable, Hashable {
    let id: String
    let brandUserId: String
    let brandCompany: String?
    let creatorUserId: String
    let creatorUsername: String?
    let creatorAge: Int?
    let creatorFollowers: Int?
    let desiredBasis: String
    let desiredAmountCents: Int
    let message: String?
    let termsBasis: String?
    let termsAmountCents: Int?
    let termsNotes: String?
    let termsDeliverables: String?
    let termsExclusive: Bool
    let termsExpiresAt: String?
    let status: String
    let createdAt: String?

    nonisolated static func from(_ dict: [String: Any]) -> WhisperSponsorApplication? {
        guard let id = dict["id"] as? String,
              let brandUserId = dict["brand_user_id"] as? String,
              let creatorUserId = dict["creator_user_id"] as? String else { return nil }
        return WhisperSponsorApplication(
            id: id,
            brandUserId: brandUserId,
            brandCompany: dict["brand_company"] as? String,
            creatorUserId: creatorUserId,
            creatorUsername: dict["creator_username"] as? String,
            creatorAge: dict["creator_age"] as? Int,
            creatorFollowers: dict["creator_followers"] as? Int,
            desiredBasis: (dict["desired_basis"] as? String) ?? "per_post",
            desiredAmountCents: (dict["desired_amount_cents"] as? Int) ?? 0,
            message: dict["message"] as? String,
            termsBasis: dict["terms_basis"] as? String,
            termsAmountCents: dict["terms_amount_cents"] as? Int,
            termsNotes: dict["terms_notes"] as? String,
            termsDeliverables: dict["terms_deliverables"] as? String,
            termsExclusive: (dict["terms_exclusive"] as? Bool) ?? false,
            termsExpiresAt: dict["terms_expires_at"] as? String,
            status: (dict["status"] as? String) ?? "pending",
            createdAt: dict["created_at"] as? String
        )
    }
}

/// An accepted sponsorship (the working agreement).
nonisolated struct WhisperSponsorDeal: Sendable, Identifiable, Hashable {
    let id: String
    let brandUserId: String
    let brandCompany: String?
    let creatorUserId: String
    let creatorUsername: String?
    let basis: String
    let amountCents: Int
    let notes: String?
    let deliverables: String?
    let exclusive: Bool
    let status: String
    let createdAt: String?

    nonisolated var basisEnum: WhisperSponsorBasis {
        WhisperSponsorBasis(rawValue: basis) ?? .perPost
    }

    nonisolated static func from(_ dict: [String: Any]) -> WhisperSponsorDeal? {
        guard let id = dict["id"] as? String,
              let brandUserId = dict["brand_user_id"] as? String,
              let creatorUserId = dict["creator_user_id"] as? String else { return nil }
        return WhisperSponsorDeal(
            id: id,
            brandUserId: brandUserId,
            brandCompany: dict["brand_company"] as? String,
            creatorUserId: creatorUserId,
            creatorUsername: dict["creator_username"] as? String,
            basis: (dict["basis"] as? String) ?? "per_post",
            amountCents: (dict["amount_cents"] as? Int) ?? 0,
            notes: dict["notes"] as? String,
            deliverables: dict["deliverables"] as? String,
            exclusive: (dict["exclusive"] as? Bool) ?? false,
            status: (dict["status"] as? String) ?? "active",
            createdAt: dict["created_at"] as? String
        )
    }
}

/// One escrow ledger entry — pending until obligations are met.
nonisolated struct WhisperSponsorPayment: Sendable, Identifiable, Hashable {
    let id: String
    let dealId: String
    let grossCents: Int
    let feeCents: Int
    let netCents: Int
    let status: String
    let requiresPost: Bool
    let holdUntil: String?
    let releasedAt: String?
    let createdAt: String?

    nonisolated static func from(_ dict: [String: Any]) -> WhisperSponsorPayment? {
        guard let id = dict["id"] as? String,
              let dealId = dict["deal_id"] as? String else { return nil }
        return WhisperSponsorPayment(
            id: id,
            dealId: dealId,
            grossCents: (dict["gross_cents"] as? Int) ?? 0,
            feeCents: (dict["fee_cents"] as? Int) ?? 0,
            netCents: (dict["net_cents"] as? Int) ?? 0,
            status: (dict["status"] as? String) ?? "pending",
            requiresPost: (dict["requires_post"] as? Bool) ?? false,
            holdUntil: dict["hold_until"] as? String,
            releasedAt: dict["released_at"] as? String,
            createdAt: dict["created_at"] as? String
        )
    }
}

/// A creator post tracked against a deal.
nonisolated struct WhisperSponsorPost: Sendable, Identifiable, Hashable {
    let id: String
    let dealId: String
    let postId: String
    let likesCount: Int
    let commentsCount: Int
    let createdAt: String?

    nonisolated static func from(_ dict: [String: Any]) -> WhisperSponsorPost? {
        guard let id = dict["id"] as? String,
              let dealId = dict["deal_id"] as? String,
              let postId = dict["post_id"] as? String else { return nil }
        return WhisperSponsorPost(
            id: id,
            dealId: dealId,
            postId: postId,
            likesCount: (dict["likes_count"] as? Int) ?? 0,
            commentsCount: (dict["comments_count"] as? Int) ?? 0,
            createdAt: dict["created_at"] as? String
        )
    }
}

/// The creator/athlete earnings gateway payload — escrow totals + payouts.
nonisolated struct WhisperCreatorEarnings: Sendable {
    let pendingCents: Int
    let releasedCents: Int
    let refundedCents: Int
    let payoutsEnabled: Bool
}

/// Whether the signed-in creator can apply to a brand, and why not.
nonisolated struct WhisperSponsorEligibility: Sendable {
    let eligible: Bool
    let blocked: Bool
    let followers: Int
    let posts: Int
    let minFollowers: Int
    let minAge: Int
    let minPosts: Int
    let reasons: [String]
}

// MARK: - Service

/// Client for the brand + sponsorship backend (Cloudflare functions) and
/// the DM-block table. Mirrors the web app's `lib/brands.ts`.
@MainActor
@Observable
final class WhisperBrandService {
    static let shared = WhisperBrandService()

    private let client = SupabaseService.shared.client

    /// Cached: the signed-in user's own brand profile (nil = not a brand).
    var myBrand: WhisperBrandProfile?
    var didLoadMyBrand: Bool = false

    private init() {}

    private func accessToken() async throws -> String {
        try await client.auth.session.accessToken
    }

    /// Authenticated JSON request against the functions backend.
    private func request(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(WhisperBillingBackend.url)\(path)") else {
            throw WhisperBillingError.invalidURL
        }
        let accountID = AccountStorage.currentUserID
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = try await accessToken()
        try WhisperChatMediaService.checkAccount(accountID)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        try WhisperChatMediaService.checkAccount(accountID)
        guard let http = response as? HTTPURLResponse,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WhisperBillingError.networkError
        }
        if !(200...299).contains(http.statusCode) {
            let code = (json["error"] as? String) ?? ""
            if code == "not_eligible", let reasons = json["reasons"] as? [String], !reasons.isEmpty {
                throw WhisperBrandError.notEligible(reasons)
            }
            throw WhisperBillingError.backendError(code: code, status: http.statusCode)
        }
        return json
    }

    // MARK: Brand profiles

    /// Public directory of published brands.
    func fetchBrands() async throws -> [WhisperBrandProfile] {
        guard let url = URL(string: "\(WhisperBillingBackend.url)/brands") else {
            throw WhisperBillingError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["brands"] as? [[String: Any]] else { return [] }
        return rows.compactMap { WhisperBrandProfile.from($0) }
    }

    /// One brand profile (published, or the caller's own draft).
    func fetchBrand(userId: String) async throws -> WhisperBrandProfile? {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId
        let json = try await request(path: "/brand/profile?userId=\(encoded)")
        guard let dict = json["brand"] as? [String: Any] else { return nil }
        return WhisperBrandProfile.from(dict)
    }

    /// Loads (and caches) the signed-in user's own brand profile.
    @discardableResult
    func refreshMyBrand() async -> WhisperBrandProfile? {
        let me = AccountStorage.currentUserID.lowercased()
        guard !me.isEmpty else { return nil }
        let brand = try? await fetchBrand(userId: me)
        guard !Task.isCancelled, AccountStorage.currentUserID.lowercased() == me else { return nil }
        myBrand = brand ?? nil
        didLoadMyBrand = true
        return myBrand
    }

    /// Create or update the caller's brand profile (the brand signup).
    func saveBrandProfile(_ input: [String: Any]) async throws {
        let accountID = AccountStorage.currentUserID
        try WhisperChatMediaService.checkAccount(accountID)
        // Older servers treat absent showcase keys as clears. Preserve the newest
        // server values, and abort on a failed read rather than guessing empty media.
        let existing = try await fetchBrand(userId: accountID.lowercased())
        try WhisperChatMediaService.checkAccount(accountID)
        var payload = input
        if payload["coverUrl"] == nil { payload["coverUrl"] = existing?.coverUrl ?? "" }
        if payload["videoUrl"] == nil { payload["videoUrl"] = existing?.videoUrl ?? "" }
        if payload["mediaUrls"] == nil { payload["mediaUrls"] = existing?.mediaUrls ?? [] }
        let response = try await request(path: "/brand/profile", method: "POST", body: payload)
        try WhisperChatMediaService.checkAccount(accountID)
        await refreshMyBrand()
        if response["mediaPending"] as? Bool == true {
            throw NSError(domain: "WhisperBrand", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Your profile details were saved, but showcase media needs a server update before it can be saved."])
        }
    }

    // MARK: Applications

    /// Can the signed-in creator apply to this brand?
    func fetchEligibility(brandUserId: String) async throws -> WhisperSponsorEligibility {
        let encoded = brandUserId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? brandUserId
        let json = try await request(path: "/brand/eligibility?brandUserId=\(encoded)")
        return WhisperSponsorEligibility(
            eligible: (json["eligible"] as? Bool) ?? false,
            blocked: (json["blocked"] as? Bool) ?? false,
            followers: (json["followers"] as? Int) ?? 0,
            posts: (json["posts"] as? Int) ?? 0,
            minFollowers: (json["minFollowers"] as? Int) ?? 0,
            minAge: (json["minAge"] as? Int) ?? 18,
            minPosts: (json["minPosts"] as? Int) ?? 0,
            reasons: (json["reasons"] as? [String]) ?? []
        )
    }

    /// Creator applies for a sponsorship.
    func apply(
        brandUserId: String,
        basis: WhisperSponsorBasis,
        amountCents: Int,
        message: String,
        age: Int
    ) async throws {
        _ = try await request(path: "/brand/apply", method: "POST", body: [
            "brandUserId": brandUserId,
            "basis": basis.rawValue,
            "amountCents": amountCents,
            "message": message,
            "age": age,
        ])
    }

    /// The caller's applications, both as a brand and as a creator.
    func fetchApplications() async throws -> (asBrand: [WhisperSponsorApplication], asCreator: [WhisperSponsorApplication]) {
        let json = try await request(path: "/sponsorship/applications")
        let asBrand = ((json["asBrand"] as? [[String: Any]]) ?? [])
            .compactMap { WhisperSponsorApplication.from($0) }
        let asCreator = ((json["asCreator"] as? [[String: Any]]) ?? [])
            .compactMap { WhisperSponsorApplication.from($0) }
        return (asBrand, asCreator)
    }

    /// Brand responds: accept, deny, or counter with edited terms.
    func respond(
        applicationId: String,
        action: String,
        termsBasis: WhisperSponsorBasis?,
        termsAmountCents: Int?,
        termsNotes: String?,
        termsDeliverables: String? = nil,
        termsExclusive: Bool? = nil,
        expiresInDays: Int? = nil
    ) async throws {
        var body: [String: Any] = ["id": applicationId, "action": action]
        if let termsBasis { body["termsBasis"] = termsBasis.rawValue }
        if let termsAmountCents { body["termsAmountCents"] = termsAmountCents }
        if let termsNotes { body["termsNotes"] = termsNotes }
        if let termsDeliverables { body["termsDeliverables"] = termsDeliverables }
        if let termsExclusive { body["termsExclusive"] = termsExclusive }
        if let expiresInDays, expiresInDays > 0 { body["expiresInDays"] = expiresInDays }
        _ = try await request(path: "/sponsorship/respond", method: "POST", body: body)
    }

    /// Persist Jasper's Instagram verification verdict on the caller's brand.
    func saveVerification(
        instagram: String,
        verified: Bool,
        score: Int,
        summary: String
    ) async throws {
        _ = try await request(path: "/brand/verify", method: "POST", body: [
            "instagram": instagram,
            "verified": verified,
            "score": score,
            "summary": summary,
        ])
        await refreshMyBrand()
    }

    /// Brand disputes a still-pending escrow payment — refunds it via Stripe.
    func disputePayment(paymentId: String, reason: String) async throws {
        _ = try await request(path: "/sponsorship/dispute", method: "POST", body: [
            "paymentId": paymentId,
            "reason": reason,
        ])
    }

    /// The creator/athlete earnings gateway — escrow totals + payout status.
    func fetchCreatorEarnings() async throws -> WhisperCreatorEarnings {
        let json = try await request(path: "/creator/earnings")
        return WhisperCreatorEarnings(
            pendingCents: (json["pendingCents"] as? Int) ?? 0,
            releasedCents: (json["releasedCents"] as? Int) ?? 0,
            refundedCents: (json["refundedCents"] as? Int) ?? 0,
            payoutsEnabled: (json["payoutsEnabled"] as? Bool) ?? false
        )
    }

    /// Uploads a brand logo image to the shared media bucket and returns
    /// its public URL.
    func uploadLogo(_ data: Data) async throws -> String {
        let me = AccountStorage.currentUserID.lowercased()
        let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) ?? data
        let path = "\(me)/brand-logo-\(UUID().uuidString.prefix(8)).jpg"
        _ = try await client.storage
            .from("whisper-media")
            .upload(
                path,
                data: jpeg,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )
        let url = try client.storage
            .from("whisper-media")
            .getPublicURL(path: path)
        return url.absoluteString
    }

    /// Creator accepts a counter-offer or withdraws their application.
    func creatorRespond(applicationId: String, action: String) async throws {
        _ = try await request(
            path: "/sponsorship/creator-respond",
            method: "POST",
            body: ["id": applicationId, "action": action]
        )
    }

    // MARK: Deals

    /// The caller's deals with the payment ledger + tracked posts.
    func fetchDeals() async throws -> (
        deals: [WhisperSponsorDeal],
        payments: [WhisperSponsorPayment],
        posts: [WhisperSponsorPost]
    ) {
        let json = try await request(path: "/sponsorship/deals")
        let deals = ((json["deals"] as? [[String: Any]]) ?? [])
            .compactMap { WhisperSponsorDeal.from($0) }
        let payments = ((json["payments"] as? [[String: Any]]) ?? [])
            .compactMap { WhisperSponsorPayment.from($0) }
        let posts = ((json["posts"] as? [[String: Any]]) ?? [])
            .compactMap { WhisperSponsorPost.from($0) }
        return (deals, payments, posts)
    }

    /// Brand funds the next payment for a deal — returns a Stripe Checkout URL.
    func fundDeal(dealId: String) async throws -> URL {
        let json = try await request(path: "/sponsorship/fund", method: "POST", body: [
            "dealId": dealId,
            "origin": WhisperBillingBackend.webOrigin,
        ])
        guard let urlString = json["url"] as? String, let url = URL(string: urlString) else {
            throw WhisperBillingError.backendError(code: "stripe_error", status: 502)
        }
        return url
    }

    /// Creator links one of their posts to a deal (fulfills the obligation).
    func trackPost(dealId: String, postId: String) async throws {
        _ = try await request(path: "/sponsorship/track-post", method: "POST", body: [
            "dealId": dealId,
            "postId": postId,
        ])
    }

    /// The creator's recent posts, for the "link a post" picker.
    func fetchMyRecentPosts() async throws -> [WhisperPostRow] {
        let me = AccountStorage.currentUserID.lowercased()
        guard !me.isEmpty else { return [] }
        let rows: [WhisperPostRow] = try await client
            .from("whisper_posts")
            .select()
            .eq("user_id", value: me)
            .order("created_at", ascending: false)
            .limit(25)
            .execute()
            .value
        return rows
    }

    // MARK: DM blocks

    /// True when `senderID` was DM-blocked from messaging `recipientID`
    /// (a brand whose sponsorship denial protects the creator from spam).
    func isDMBlocked(senderID: String, recipientID: String) async -> Bool {
        guard !senderID.isEmpty, !recipientID.isEmpty else { return false }
        struct BlockRow: Codable { let id: String }
        do {
            let rows: [BlockRow] = try await client
                .from("whisper_dm_blocks")
                .select("id")
                .eq("blocked_sender_id", value: senderID)
                .eq("protected_user_id", value: recipientID)
                .limit(1)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            // Table missing or offline — never block sends by accident.
            return false
        }
    }
}

// MARK: - Errors

nonisolated enum WhisperBrandError: LocalizedError {
    case notEligible([String])

    nonisolated var errorDescription: String? {
        switch self {
        case .notEligible(let reasons):
            return reasons.joined(separator: "\n")
        }
    }
}
