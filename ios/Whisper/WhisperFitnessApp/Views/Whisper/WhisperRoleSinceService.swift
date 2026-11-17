import Foundation
import SwiftUI
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// -- Track when a user was granted each role so the role pill on the
// -- profile can say "Verified since Mar 2024" etc. Nullable so existing
// -- rows keep working until the next role flip backfills the date.
// alter table public.usernames
//   add column if not exists verified_since  timestamptz,
//   add column if not exists moderator_since timestamptz,
//   add column if not exists admin_since     timestamptz,
//   add column if not exists owner_since     timestamptz;
// alter table public.profiles
//   add column if not exists verified_since  timestamptz,
//   add column if not exists moderator_since timestamptz,
//   add column if not exists admin_since     timestamptz,
//   add column if not exists owner_since     timestamptz;
// alter table public.whisper_profiles
//   add column if not exists coach_since   timestamptz,
//   add column if not exists athlete_since timestamptz;

/// Caches "role grant" dates for users so tapping the role pill on a
/// profile (Coach, Verified, Athlete, Admin, Moderator, Founder) can show
/// how long the user has held that role.
///
/// All fetches tolerate missing columns silently — if the schema hasn't
/// been migrated yet, the service falls back to `whisper_profiles.created_at`
/// (account join date) so the sheet still surfaces a meaningful "Active
/// since…" line instead of looking broken.
@MainActor
@Observable
final class WhisperRoleSinceService {
    static let shared = WhisperRoleSinceService()

    private let client = SupabaseService.shared.client

    /// Cached dates keyed by `"\(lowercased_username):\(role.text)"`.
    private(set) var cache: [String: Date] = [:]
    /// Cached account-join dates keyed by lowercased username. Used as the
    /// fallback line when no role-specific date is available.
    private(set) var joinDates: [String: Date] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    private func cacheKey(username: String, role: String) -> String {
        "\(username.lowercased()):\(role.lowercased())"
    }

    func date(forUsername username: String, role: WhisperRoleDescriptor) -> Date? {
        cache[cacheKey(username: username, role: role.text)]
    }

    func joinDate(forUsername username: String) -> Date? {
        joinDates[username.lowercased()]
    }

    /// Pulls the role-grant date and the account join date for `username`.
    /// Safe to call repeatedly — in-flight requests are deduped and cached.
    func preload(username rawUsername: String, userID: String?) async {
        let username = rawUsername.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !inFlight.contains(username) else { return }
        inFlight.insert(username)
        defer { inFlight.remove(username) }

        // Account join date from whisper_profiles. Best-effort.
        await fetchWhisperJoin(username: username, userID: userID)
        // Role-specific dates from usernames / profiles.
        await fetchUsernamesRoles(username: username)
    }

    private func fetchWhisperJoin(username: String, userID: String?) async {
        nonisolated struct Row: Codable, Sendable {
            let user_id: String?
            let username: String?
            let onboarded_at: String?
            let coach_since: String?
            let athlete_since: String?
        }
        do {
            let base = client
                .from("whisper_profiles")
                .select("user_id,username,onboarded_at,coach_since,athlete_since")
            let rows: [Row]
            if let uid = userID, !uid.isEmpty, uid != "guest", !uid.hasPrefix("local_") {
                rows = try await base.eq("user_id", value: uid).limit(1).execute().value
            } else {
                rows = try await base.ilike("username", pattern: username).limit(1).execute().value
            }
            guard let row = rows.first else { return }
            if let s = row.onboarded_at, let d = Self.parseISO(s) {
                joinDates[username] = d
            }
            if let s = row.coach_since, let d = Self.parseISO(s) {
                cache[cacheKey(username: username, role: WhisperRoleDescriptor.coach.text)] = d
            }
            // The athlete badge is a Creator niche now — a legacy athlete_since
            // date reads as the verified (creator) "since" when nothing newer
            // has been recorded for the verified role.
            if let s = row.athlete_since, let d = Self.parseISO(s) {
                let key = cacheKey(username: username, role: WhisperRoleDescriptor.verified.text)
                if cache[key] == nil { cache[key] = d }
            }
        } catch {
            // Silent — column may not exist yet on the older schema.
        }
    }

    private func fetchUsernamesRoles(username: String) async {
        nonisolated struct Row: Codable, Sendable {
            let username: String?
            let verified_since: String?
            let moderator_since: String?
            let admin_since: String?
            let owner_since: String?
        }
        do {
            let rows: [Row] = try await client
                .from("usernames")
                .select("username,verified_since,moderator_since,admin_since,owner_since")
                .ilike("username", pattern: username)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return }
            if let s = row.verified_since, let d = Self.parseISO(s) {
                cache[cacheKey(username: username, role: WhisperRoleDescriptor.verified.text)] = d
            }
            if let s = row.moderator_since, let d = Self.parseISO(s) {
                cache[cacheKey(username: username, role: WhisperRoleDescriptor.moderator.text)] = d
            }
            if let s = row.admin_since, let d = Self.parseISO(s) {
                cache[cacheKey(username: username, role: WhisperRoleDescriptor.admin.text)] = d
            }
            if let s = row.owner_since, let d = Self.parseISO(s) {
                cache[cacheKey(username: username, role: WhisperRoleDescriptor.owner.text)] = d
            }
        } catch {
            // Silent — columns may not exist yet.
        }
    }

    nonisolated static func parseISO(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    /// "March 2024" style human label for a date.
    nonisolated static func monthYear(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }
}

// MARK: - Tappable role pill + info sheet

/// Wraps `WhisperRolePill` in a Button that surfaces a small popover-style
/// sheet describing the role and how long the user has held it.
struct WhisperRolePillButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let descriptor: WhisperRoleDescriptor
    let username: String
    let userID: String?

    @State private var presentInfo: Bool = false
    @State private var sinceService = WhisperRoleSinceService.shared

    var body: some View {
        Button {
            Haptics.tap()
            presentInfo = true
            Task { await sinceService.preload(username: username, userID: userID) }
        } label: {
            WhisperRolePill(descriptor: descriptor)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presentInfo) {
            WhisperRoleSinceSheet(
                descriptor: descriptor,
                username: username,
                userID: userID
            )
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(22)
        }
    }
}

/// Compact bottom sheet shown when the user taps a role pill on a profile.
/// Renders the role's icon, name, and a "Since {Month Year}" line resolved
/// from `WhisperRoleSinceService`. Falls back to the user's whisper join
/// date when no role-specific column is set.
struct WhisperRoleSinceSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let descriptor: WhisperRoleDescriptor
    let username: String
    let userID: String?

    @State private var sinceService = WhisperRoleSinceService.shared

    private var sinceDate: Date? {
        sinceService.date(forUsername: username, role: descriptor)
    }

    private var joinDate: Date? {
        sinceService.joinDate(forUsername: username)
    }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(descriptor.tint.opacity(colorScheme == .dark ? 0.22 : 0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: descriptor.systemImage)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(descriptor.tint)
                }
                .padding(.top, 12)

                Text(descriptor.text)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))

                sinceLine
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
        }
        .task {
            await sinceService.preload(username: username, userID: userID)
        }
    }

    @ViewBuilder
    private var sinceLine: some View {
        if let d = sinceDate {
            Text("\(descriptor.text) since \(WhisperRoleSinceService.monthYear(d))")
        } else if let d = joinDate {
            Text("Active on Whisper since \(WhisperRoleSinceService.monthYear(d))")
        } else {
            Text("Recognized member of the Whisper community.")
        }
    }
}
