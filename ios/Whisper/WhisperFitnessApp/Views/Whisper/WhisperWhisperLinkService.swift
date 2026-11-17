import Foundation
import SwiftUI
import UIKit
import Supabase

/// Whisper's side of the optional "Connect Whisper" account-linking flow.
///
/// Whisper is the primary fitness identity; Whisper keeps its own auth. Linking
/// is always optional — a signed-in Whisper user consents (via a deep-link
/// "Allow" in Whisper, or by pasting an 8-char code), after which Whisper can
/// read that user's `jasper_*` bridge tables through `jasper_uid_for()`.
///
/// Whisper owns the schema + RPCs (`redeem_jasper_link_code`, `revoke_jasper_link`,
/// `jasper_uid_for`) and the `account_links` table — we only call them. Every
/// RPC stamps `auth.uid()` server-side, so the mapping can't be forged.
@MainActor
@Observable
final class WhisperWhisperLinkService {
    static let shared = WhisperWhisperLinkService()

    /// Whether the signed-in Whisper user currently has an active Whisper link.
    private(set) var isLinked: Bool = false
    /// The linked Whisper user id (from `account_links.jasper_uid`) when linked.
    private(set) var jasperUID: String?
    /// ISO timestamp the link was established, for display.
    private(set) var linkedAt: String?
    /// In-flight flag so the UI can show progress + disable buttons.
    var isBusy: Bool = false
    /// Last user-facing status/error message surfaced by the connect UI.
    var statusMessage: String?
    /// Bumped when Jasper's Allow screen comes back with "denied" — lets the
    /// one-button connect flow observe the rejection and clean up after itself.
    private(set) var lastDeniedAt: Date?
    /// Bumped on EVERY successful redeem — even a re-link when `isLinked` was
    /// already true — so the one-button flow always gets a completion signal.
    private(set) var lastLinkedAt: Date?
    /// `isLinked` at the moment the current Allow round-trip began — lets the
    /// foreground fallback tell a freshly landed link from a pre-existing one.
    private var wasLinkedWhenDeepLinkBegan = false

    private let client = SupabaseService.shared.client
    /// Persisted so a verifiable `state` survives Whisper being backgrounded
    /// while the user taps Allow in Whisper.
    private let pendingStateKey = "whisper.jasperLink.pendingState"

    private init() {}

    func resetForAccountChange() {
        isLinked = false; jasperUID = nil; linkedAt = nil
        isBusy = false; statusMessage = nil
        lastDeniedAt = nil; lastLinkedAt = nil
        wasLinkedWhenDeepLinkBegan = false
    }

    // MARK: - Status

    private nonisolated struct AccountLinkRow: Decodable {
        let jasper_uid: String
        let linked_at: String?
        let revoked_at: String?
    }

    /// Refreshes `isLinked` / `jasperUID` from `account_links`. RLS scopes the
    /// query to the caller's own row, so a non-empty, non-revoked result means
    /// linked. Temporary failures retain the last confirmed state for this owner.
    @discardableResult
    func refreshStatus() async -> Bool {
        let generation = AccountStorage.generation
        do {
            let context = try await JasperAccountSession.current()
            let rows: [AccountLinkRow] = try await client
                .from("account_links")
                .select("jasper_uid, linked_at, revoked_at")
                .execute()
                .value
            try context.check()
            let active = rows.first { $0.revoked_at == nil }
            isLinked = active != nil
            jasperUID = active?.jasper_uid
            linkedAt = active?.linked_at
            return isLinked
        } catch {
            guard generation == AccountStorage.generation, !Task.isCancelled else { return false }
            statusMessage = "Couldn't check Jasper right now. Your saved connection hasn't been removed."
            return false
        }
    }

    // MARK: - Deep-link "Allow" flow (primary path)

    /// True when Whisper appears to be installed (so we can run the one-tap
    /// Allow flow). When false, the UI should fall back to pasting a code.
    var isWhisperInstalled: Bool {
        guard let url = URL(string: "jasper://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Opens Whisper's consent screen:
    /// `jasper://link?app=whisper&state=<RANDOM>&redirect=whisper`.
    /// Stores the random `state` so we can verify Whisper's echoed value on
    /// return. Returns false (without opening) when Whisper isn't installed —
    /// the caller should then show the paste-a-code fallback.
    @discardableResult
    func beginDeepLink() -> Bool {
        guard AuthenticationService.shared.isSignedIn, isWhisperInstalled else { return false }
        wasLinkedWhenDeepLinkBegan = isLinked
        let state = UUID().uuidString
        AccountStorage.set(state, forKey: pendingStateKey)
        var components = URLComponents()
        components.scheme = "jasper"
        components.host = "link"
        components.queryItems = [
            URLQueryItem(name: "app", value: "whisper"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect", value: "whisper"),
        ]
        guard let url = components.url else { return false }
        UIApplication.shared.open(url)
        return true
    }

    /// Handles Whisper's return deep link. Returns true when the URL was a
    /// `whisper://linked` response (so `onOpenURL` can stop routing it
    /// elsewhere). On an allowed return it verifies `state`, then silently
    /// redeems the handed-back code and refreshes status.
    ///
    /// - Allowed: `whisper://linked?code=<CODE>&state=<STATE>`
    /// - Denied:  `whisper://linked?denied=1&state=<STATE>`
    @discardableResult
    func handleReturn(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "whisper",
              url.host?.lowercased() == "linked" else { return false }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        let expectedState = AccountStorage.string(forKey: pendingStateKey)
        let returnedState = value("state")
        // Verify the opaque state we sent. On mismatch KEEP the pending
        // state — a stale consent screen (the user tapped "Open Jasper
        // again") can still deliver the current state a moment later.
        guard let expectedState, !expectedState.isEmpty,
              returnedState == expectedState else {
            return true
        }
        if value("denied") == "1" {
            AccountStorage.set("", forKey: pendingStateKey)
            statusMessage = "Connection cancelled."
            lastDeniedAt = Date()
            return true
        }

        guard let code = value("code"), !code.isEmpty else {
            statusMessage = "Couldn't read the code from Jasper. Try again."
            return true
        }

        let generation = AccountStorage.generation
        Task {
            let deadline = Date().addingTimeInterval(15)
            while AuthenticationService.shared.isRestoringSession, Date() < deadline {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard generation == AccountStorage.generation else { return }
            }
            guard generation == AccountStorage.generation, AuthenticationService.shared.isSignedIn else { return }
            let outcome = await redeem(code: code, silent: true)
            guard generation == AccountStorage.generation else { return }
            if outcome == .linked || outcome == .invalidOrExpired || outcome == .selfLink {
                AccountStorage.set("", forKey: pendingStateKey)
            }
        }
        return true
    }

    /// True while a deep-link Allow round-trip is outstanding.
    var hasPendingDeepLink: Bool {
        !(AccountStorage.string(forKey: pendingStateKey) ?? "").isEmpty
    }

    /// Foreground fallback for round-trips where the return deep link never
    /// arrives (or landed in a previous process): if the link exists
    /// server-side, finish exactly like the deep-link happy path so the
    /// connect card can mint the token and play the celebration.
    func checkPendingReturn() async {
        guard hasPendingDeepLink, !wasLinkedWhenDeepLinkBegan else { return }
        let generation = AccountStorage.generation
        guard await refreshStatus(), generation == AccountStorage.generation, !Task.isCancelled else { return }
        AccountStorage.set("", forKey: pendingStateKey)
        statusMessage = "Connected to Jasper."
        lastLinkedAt = Date()
        Haptics.success()
    }

    // MARK: - Redeem (deep link + paste fallback)

    enum RedeemOutcome: Equatable {
        case linked
        case invalidOrExpired
        case selfLink
        case notAuthenticated
        case failed
    }

    /// Redeems an 8-char link code as the signed-in Whisper user. The server
    /// trims/upper-cases, so raw user input is fine. On success refreshes link
    /// status. `silent` skips the "Enter the code" framing for the deep-link
    /// happy path where the user never typed anything.
    @discardableResult
    func redeem(code: String, silent: Bool = false) async -> RedeemOutcome {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter the code from Jasper."
            return .invalidOrExpired
        }
        guard !isBusy else { return .failed }
        let generation = AccountStorage.generation
        isBusy = true
        defer { if generation == AccountStorage.generation { isBusy = false } }

        nonisolated struct Params: Encodable { let p_code: String }
        do {
            let context = try await JasperAccountSession.current()
            let jasper: String = try await client
                .rpc("redeem_jasper_link_code", params: Params(p_code: trimmed))
                .execute()
                .value
            try context.check()
            jasperUID = jasper
            isLinked = true
            await refreshStatus()
            try context.check()
            statusMessage = "Connected to Jasper."
            lastLinkedAt = Date()
            Haptics.success()
            return .linked
        } catch {
            guard generation == AccountStorage.generation, !Task.isCancelled else { return .failed }
            let outcome = Self.classify(error)
            switch outcome {
            case .invalidOrExpired:
                statusMessage = silent
                    ? "That link expired. Tap Connect Jasper again to retry."
                    : "Invalid or expired code. Codes last 10 minutes — grab a fresh one in Jasper."
            case .selfLink:
                statusMessage = "That's the same account — link a different Jasper account."
            case .notAuthenticated:
                statusMessage = "Sign in to Whisper first, then connect Jasper."
            default:
                statusMessage = "Couldn't connect right now. Please try again."
            }
            Haptics.warning()
            return outcome
        }
    }

    /// Maps a Postgres RPC error to a known outcome by inspecting its message.
    private static func classify(_ error: Error) -> RedeemOutcome {
        let text = String(describing: error).lowercased()
        if text.contains("invalid or expired") { return .invalidOrExpired }
        if text.contains("itself") { return .selfLink }
        if text.contains("not authenticated") { return .notAuthenticated }
        return .failed
    }

    // MARK: - Disconnect

    /// Revokes the current Whisper user's Whisper link (either side may revoke).
    @discardableResult
    func disconnect() async -> Bool {
        guard !isBusy else { return false }
        let generation = AccountStorage.generation
        isBusy = true
        defer { if generation == AccountStorage.generation { isBusy = false } }
        do {
            let context = try await JasperAccountSession.current()
            try await client.rpc("revoke_jasper_link").execute()
            try context.check()
            isLinked = false
            jasperUID = nil
            linkedAt = nil
            statusMessage = "Disconnected from Jasper."
            Haptics.tap()
            return true
        } catch {
            guard generation == AccountStorage.generation, !Task.isCancelled else { return false }
            statusMessage = "Couldn't disconnect right now. Please try again."
            return false
        }
    }

    // MARK: - Reading bridge data

    /// Resolves which Whisper id the current user reads as: the linked
    /// `jasper_uid` if linked, otherwise the caller's own `auth.uid()`. Use
    /// this when querying any `jasper_*` bridge table — never assume
    /// `auth.uid()` equals the Whisper id.
    func resolvedWhisperUID() async -> String? {
        do {
            let context = try await JasperAccountSession.current()
            let uid: String = try await client
                .rpc("jasper_uid_for")
                .execute()
                .value
            try context.check()
            return uid
        } catch {
            return nil
        }
    }
}
