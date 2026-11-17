import Foundation
import SwiftUI
import Supabase

/// Tracks per-user "last seen" timestamps so the DM header can show
/// "Active now", "Active 5 min ago", etc. like Instagram.
///
/// Backed by a tiny `whisper_presence` table:
///
/// ```sql
/// create table if not exists public.whisper_presence (
///   user_id uuid primary key references auth.users(id) on delete cascade,
///   last_seen_at timestamptz not null default now()
/// );
/// alter table public.whisper_presence enable row level security;
/// create policy "presence read all" on public.whisper_presence
///   for select using (true);
/// create policy "presence upsert self" on public.whisper_presence
///   for insert with check (auth.uid() = user_id);
/// create policy "presence update self" on public.whisper_presence
///   for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
/// ```
///
/// The local user heartbeats every 30 seconds while the app is foreground.
/// Anyone we look up gets cached in `lastSeenByUser` and a friendly
/// "Active …" label is exposed via ``activeLabel(forUserID:)``.
@MainActor
@Observable
final class WhisperPresenceService {
    static let shared = WhisperPresenceService()

    private let client = SupabaseService.shared.client
    private var heartbeatTask: Task<Void, Never>?
    private(set) var lastSeenByUser: [String: Date] = [:]

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {}

    // MARK: - Heartbeat

    nonisolated private struct PresenceRow: Codable, Sendable {
        let user_id: String
        let last_seen_at: String
    }

    nonisolated private struct PresenceReadRow: Decodable, Sendable {
        let user_id: String
        let last_seen_at: String?
    }

    /// Begin emitting heartbeats while the app is active. Idempotent.
    func startHeartbeat() {
        guard isRemote, heartbeatTask == nil else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.beat()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// Single-shot upsert (also called by the periodic heartbeat).
    func beat() async {
        guard isRemote else { return }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let owner = currentUID
        let generation = AccountStorage.generation
        let row = PresenceRow(user_id: owner, last_seen_at: iso.string(from: Date()))
        do {
            try await client
                .from("whisper_presence")
                .upsert(row, onConflict: "user_id")
                .execute()
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return }
            lastSeenByUser[owner.lowercased()] = Date()
        } catch {
            // Table may not be deployed yet — silently no-op so the UI just
            // hides the "Active …" label instead of showing an error.
            print("[Presence] beat failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Reads

    /// Refresh `lastSeenByUser` for a single peer. Returns the date (or nil
    /// if the row is missing / the table isn't deployed).
    @discardableResult
    func refresh(userID: String) async -> Date? {
        guard isRemote, !userID.isEmpty else { return nil }
        let generation = AccountStorage.generation
        do {
            let rows: [PresenceReadRow] = try await client
                .from("whisper_presence")
                .select("user_id,last_seen_at")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation,
                  let raw = rows.first?.last_seen_at,
                  let date = WhisperBackendService.parseISO(raw) else { return nil }
            lastSeenByUser[userID.lowercased()] = date
            return date
        } catch {
            return nil
        }
    }

    /// Bulk refresh for the inbox.
    func refresh(userIDs: [String]) async {
        let ids = userIDs.filter { !$0.isEmpty && $0 != "guest" && !$0.hasPrefix("local_") }
        guard isRemote, !ids.isEmpty else { return }
        do {
            let rows: [PresenceReadRow] = try await client
                .from("whisper_presence")
                .select("user_id,last_seen_at")
                .in("user_id", values: ids)
                .execute()
                .value
            for r in rows {
                if let raw = r.last_seen_at, let date = WhisperBackendService.parseISO(raw) {
                    lastSeenByUser[r.user_id.lowercased()] = date
                }
            }
        } catch {
            // Quietly degrade — header will just hide the line.
        }
    }

    // MARK: - Display

    /// Returns "Active now", "Active 5 min ago", "Active 2 hr ago",
    /// "Active yesterday" — or `nil` if we have no last-seen for this user.
    func activeLabel(forUserID userID: String) -> String? {
        guard let date = lastSeenByUser[userID.lowercased()] else { return nil }
        return Self.activeLabel(from: date)
    }

    nonisolated static func activeLabel(from date: Date) -> String {
        let secs = Date().timeIntervalSince(date)
        if secs < 120 { return "Active now" }
        if secs < 3600 { return "Active \(Int(secs / 60)) min ago" }
        if secs < 86_400 {
            let h = Int(secs / 3600)
            return "Active \(h) hr ago"
        }
        if secs < 86_400 * 2 { return "Active yesterday" }
        let d = Int(secs / 86_400)
        if d < 7 { return "Active \(d) days ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Active " + f.string(from: date)
    }
}
