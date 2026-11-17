import Foundation
import Supabase
import UIKit

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_events (
//   id uuid primary key default gen_random_uuid(),
//   user_id uuid references auth.users(id) on delete set null,
//   session_id text not null,
//   event text not null,
//   props jsonb,
//   app_version text,
//   os_version text,
//   created_at timestamptz not null default now()
// );
// create index if not exists whisper_events_event_idx
//   on public.whisper_events (event, created_at desc);
// create index if not exists whisper_events_user_idx
//   on public.whisper_events (user_id, created_at desc);
// alter table public.whisper_events enable row level security;
// -- Signed-in users may insert their own events. Reads are owner-only by
// -- default; analytics dashboards should use the service role.
// create policy "we insert own" on public.whisper_events
//   for insert with check (
//     user_id is null or auth.uid() = user_id
//   );
// create policy "we read own" on public.whisper_events
//   for select using (auth.uid() = user_id);

nonisolated struct WhisperEventInsert: Codable, Sendable {
    let user_id: String?
    let session_id: String
    let event: String
    let props: String?  // JSON-encoded string; flexible & avoids AnyJSON cost
    let app_version: String?
    let os_version: String?
}

/// Lightweight analytics writer for Whisper. Best-effort by design: failures
/// never bubble back to the call site, so funnel calls are free to litter
/// the codebase without try/await error noise. Events are inserted into
/// `public.whisper_events` (see SQL block above).
@MainActor
@Observable
final class WhisperAnalyticsService {
    static let shared = WhisperAnalyticsService()

    /// One session per app launch. Cycles when the user signs out so
    /// downstream queries can attribute funnel steps to a single attempt.
    private(set) var sessionID: String = UUID().uuidString

    private let client = SupabaseService.shared.client

    private var currentUID: String? {
        let uid = AccountStorage.currentUserID
        if uid == "guest" || uid.hasPrefix("local_") { return nil }
        return uid
    }

    private static let appVersion: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }()

    private static let osVersion: String = {
        UIDevice.current.systemName + " " + UIDevice.current.systemVersion
    }()

    private init() {}

    /// Reset the session id — call on sign-out so the next sign-in starts a
    /// fresh funnel.
    func resetSession() {
        sessionID = UUID().uuidString
    }

    /// Fire-and-forget. Never throws. Drops silently on guest sessions.
    func record(_ event: String, _ props: [String: String] = [:]) {
        let uid = currentUID
        let session = sessionID
        let propsJSON: String? = {
            guard !props.isEmpty else { return nil }
            return try? String(data: JSONEncoder().encode(props), encoding: .utf8) ?? nil
        }()
        let row = WhisperEventInsert(
            user_id: uid,
            session_id: session,
            event: event,
            props: propsJSON,
            app_version: Self.appVersion,
            os_version: Self.osVersion
        )
        Task.detached { [client] in
            do {
                try await client.from("whisper_events").insert(row).execute()
            } catch {
                // Best-effort; never surface analytics failures to the user.
                #if DEBUG
                print("[Whisper] analytics error for \(event): \(error.localizedDescription)")
                #endif
            }
        }
    }
}

/// Tiny convenience facade so call sites read clean:
/// `Analytics.record("post_created", ["kind": "photo"])`.
enum Analytics {
    @MainActor
    static func record(_ event: String, _ props: [String: String] = [:]) {
        WhisperAnalyticsService.shared.record(event, props)
    }
}
