import Foundation
import Supabase

/// Creator links & invite codes — every Whisper user gets a shareable code.
/// Signups that enter the code (or arrive via the share link) are credited
/// to the code's owner through the backend's `/referrals/redeem` endpoint.
@MainActor
@Observable
final class WhisperReferralService {
    static let shared = WhisperReferralService()

    private let client = SupabaseService.shared.client
    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    var myCode: CodeRow?
    var signupCount: Int = 0
    var isLoading: Bool = false
    var lastError: String?

    private init() {}

    nonisolated struct CodeRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let recruiter_id: String
        let code: String
        let uses: Int
        let created_at: String?
    }

    private nonisolated struct StatsResponse: Codable, Sendable {
        let total: Int
    }

    private nonisolated struct RedeemResponse: Codable, Sendable {
        let ok: Bool?
        let error: String?
    }

    /// The shareable web link for this user's code — opens the web signup
    /// with the code prefilled.
    var shareLink: String? {
        guard let code = myCode?.code else { return nil }
        return "\(WhisperBillingBackend.webOrigin)/auth?mode=signup&code=\(code)"
    }

    /// Fetch this user's code, creating one on first use.
    func refresh() async {
        guard isRemote else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [CodeRow] = try await client
                .from("whisper_referral_codes")
                .select()
                .eq("recruiter_id", value: currentUID)
                .limit(1)
                .execute()
                .value
            if let existing = rows.first {
                myCode = existing
            } else {
                let username = WhisperUserService.shared.me?.username
                    ?? LeaderboardService.shared.savedUsername
                    ?? "WSP"
                let prefix = String(username.uppercased().filter { $0.isLetter }.prefix(4))
                let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
                let suffix = String((0..<3).compactMap { _ in chars.randomElement() })
                let code = (prefix.isEmpty ? "WSP" : prefix) + suffix
                let inserted: [CodeRow] = try await client
                    .from("whisper_referral_codes")
                    .insert(["recruiter_id": AnyJSON.string(currentUID), "code": .string(code)])
                    .select()
                    .execute()
                    .value
                myCode = inserted.first
            }
            lastError = nil
        } catch {
            lastError = "Couldn't load your creator code."
            print("[Referral] refresh error: \(error.localizedDescription)")
        }
        await refreshStats()
    }

    /// Signup credits earned so far (authoritative count from the backend).
    func refreshStats() async {
        guard isRemote,
              let url = URL(string: "\(WhisperBillingBackend.url)/referrals/stats?userId=\(currentUID.lowercased())") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let stats = try JSONDecoder().decode(StatsResponse.self, from: data)
            signupCount = stats.total
        } catch {
            // Fall back to the code row's counter.
            signupCount = myCode?.uses ?? 0
        }
    }

    /// Redeem an invite/creator code for a freshly signed-up user. Silent
    /// best-effort — a bad code never blocks the signup itself.
    /// Returns true when the code was accepted.
    @discardableResult
    static func redeem(code: String, newUserID: String) async -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty, !newUserID.isEmpty,
              let url = URL(string: "\(WhisperBillingBackend.url)/referrals/redeem") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["code": trimmed, "userId": newUserID.lowercased()]
            )
            let (_, response) = try await URLSession.shared.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            print("[Referral] redeem \(trimmed) -> \(ok ? "credited" : "not credited")")
            return ok
        } catch {
            print("[Referral] redeem failed: \(error.localizedDescription)")
            return false
        }
    }
}
