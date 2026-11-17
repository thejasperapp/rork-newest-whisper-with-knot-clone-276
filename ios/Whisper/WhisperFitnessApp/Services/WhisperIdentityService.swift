import Foundation
import Supabase

/// Single source of truth for "is the local `AccountStorage.currentUserID`
/// safe to write into Whisper / coach tables?" and for healing the case
/// where the cached UID has drifted from the live Supabase session UID
/// (e.g. user re-signed-in, Apple Hide-My-Email rotated, password reset).
///
/// Two surfaces:
///
///   * `requireValidUID()` — call at every write site that inserts a row
///     keyed by `auth.uid()`. Throws if the cached UID is `guest`, has the
///     `local_` prefix, or isn't a real UUID. Prevents orphan rows that
///     fail RLS silently.
///
///   * `checkMismatch()` + `relink(...)` — on launch we compare the live
///     `supabase.auth.session.user.id` against `AccountStorage.currentUserID`.
///     When they differ we surface a banner and offer a one-tap relink
///     that calls the security-definer RPC `whisper_relink_client_uid`,
///     which rewrites `client_user_id` from old → new across the coach
///     tables in a single transaction (gated server-side on matching email).
@MainActor
@Observable
final class WhisperIdentityService {
    static let shared = WhisperIdentityService()

    /// Populated when the live Supabase session UID differs from the cached
    /// `AccountStorage.currentUserID`. `nil` when they match (or no session).
    var mismatch: UIDMismatch?
    private(set) var isRelinking: Bool = false
    private(set) var lastError: String?

    struct UIDMismatch: Equatable, Hashable {
        let cachedUID: String
        let sessionUID: String
    }

    private let client = SupabaseService.shared.client
    private init() {}

    // MARK: - UID validation

    /// True iff `id` looks like a real Supabase `auth.users.id` (UUID v4
    /// string), not `"guest"` and not a `local_…` placeholder.
    static func isValidSupabaseUID(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != "guest",
              !trimmed.lowercased().hasPrefix("local_")
        else { return false }
        return UUID(uuidString: trimmed) != nil
    }

    /// Returns the cached UID if it's valid; throws otherwise. Use at every
    /// Whisper write site that fills `auth.uid()`-bound columns.
    @discardableResult
    static func requireValidUID() throws -> String {
        let id = AccountStorage.currentUserID
        guard isValidSupabaseUID(id) else {
            throw IdentityError.invalidLocalUID(id)
        }
        return id
    }

    enum IdentityError: LocalizedError {
        case invalidLocalUID(String)

        var errorDescription: String? {
            switch self {
            case .invalidLocalUID(let id):
                return "Account isn't linked to Supabase yet (id: \(id)). Sign in again to continue."
            }
        }
    }

    // MARK: - Launch-time reconciliation

    /// Compare the live Supabase session UID against the cached UID and
    /// populate `mismatch` if they differ. Safe to call repeatedly.
    func checkMismatch() async {
        let cached = AccountStorage.currentUserID
        guard let session = try? await client.auth.session else {
            // No live session — nothing to reconcile against.
            self.mismatch = nil
            return
        }
        let live = session.user.id.uuidString
        if cached.lowercased() == live.lowercased() {
            self.mismatch = nil
            return
        }
        // If the cached value isn't a real UID (guest / local_…) we don't
        // surface a "relink" prompt — there's no old account to merge.
        guard Self.isValidSupabaseUID(cached) else {
            self.mismatch = nil
            return
        }
        self.mismatch = UIDMismatch(cachedUID: cached, sessionUID: live)
    }

    /// Calls the security-definer RPC `whisper_relink_client_uid(old, new)`.
    /// The function verifies (server-side) that `auth.email()` matches the
    /// email on both `auth.users` rows before rewriting `client_user_id`
    /// across `whisper_coach_requests` and `whisper_coach_proposals` in one
    /// transaction. On success we point `AccountStorage` at the new UID and
    /// clear the banner.
    @discardableResult
    func relink() async -> Bool {
        guard let m = mismatch else { return false }
        isRelinking = true
        defer { isRelinking = false }
        lastError = nil

        struct Params: Encodable, Sendable {
            let old_uid: String
            let new_uid: String
        }

        do {
            try await client
                .rpc("whisper_relink_client_uid",
                     params: Params(old_uid: m.cachedUID, new_uid: m.sessionUID))
                .execute()
            // Point local state at the live session UID so subsequent writes
            // satisfy RLS.
            AccountStorage.currentUserID = m.sessionUID
            self.mismatch = nil
            return true
        } catch {
            lastError = "Couldn't relink account: \(error.localizedDescription)"
            print("[Whisper] relink RPC error: \(error)")
            return false
        }
    }

    /// Dismiss without relinking — banner stays gone for this launch only.
    func dismiss() {
        mismatch = nil
    }
}
