import Foundation
import Supabase

// MARK: - Supabase schema (additive — `whisper_reports` already exists from WhisperBlockService)
//
// -- 1) status enum widened so mods can resolve reports
// alter table public.whisper_reports
//     drop constraint if exists whisper_reports_status_check;
// alter table public.whisper_reports
//     add constraint whisper_reports_status_check
//     check (status in ('open','helpful','dismissed','actioned'));
// alter table public.whisper_reports add column if not exists reviewed_by uuid;
// alter table public.whisper_reports add column if not exists reviewed_at timestamptz;
// alter table public.whisper_reports add column if not exists review_note text;
//
// -- 2) helpful_report_count column on profiles drives the Community Guardian badge
// alter table public.profiles add column if not exists helpful_report_count int not null default 0;
//
// -- 3) RLS — mods/admins/owner can read & update every report
// drop policy if exists "reports read mod" on public.whisper_reports;
// create policy "reports read mod" on public.whisper_reports
//   for select using (
//     exists (select 1 from public.profiles p
//             where p.id = auth.uid()
//               and (p.is_moderator = true or p.is_admin = true or p.is_owner = true))
//   );
// drop policy if exists "reports update mod" on public.whisper_reports;
// create policy "reports update mod" on public.whisper_reports
//   for update using (
//     exists (select 1 from public.profiles p
//             where p.id = auth.uid()
//               and (p.is_moderator = true or p.is_admin = true or p.is_owner = true))
//   );
//
// -- 4) atomic increment for helpful_report_count (called when marking helpful)
// create or replace function public.increment_helpful_report_count(p_reporter uuid)
//   returns void
//   language sql
//   security definer
//   as $$
//     update public.profiles
//        set helpful_report_count = coalesce(helpful_report_count, 0) + 1
//      where id = p_reporter;
//   $$;
// grant execute on function public.increment_helpful_report_count(uuid) to authenticated;

nonisolated struct WhisperReportRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let reporter_id: String?
    let reporter_username: String?
    let target_kind: String
    let target_id: String?
    let target_user_id: String?
    let target_username: String?
    let reason: String
    let details: String?
    let status: String
    let review_note: String?
    let reviewed_by: String?
    let reviewed_at: Date?
    let created_at: Date?
}

nonisolated struct WhisperReportStatusUpdate: Codable, Sendable {
    let status: String
    let review_note: String?
    let reviewed_by: String?
    let reviewed_at: Date?
}

nonisolated struct WhisperReporterRPCArgs: Codable, Sendable {
    let p_reporter: String
}

/// Mod / admin / owner dashboard service for `whisper_reports`. Lets the
/// review team mark a report **helpful** (increments
/// `profiles.helpful_report_count` on the reporter, unlocking the
/// Community Guardian badge once they cross the threshold) or **dismiss** it.
@MainActor
@Observable
final class WhisperReportsService {
    static let shared = WhisperReportsService()

    private let client = SupabaseService.shared.client

    var open: [WhisperReportRow] = []
    var recent: [WhisperReportRow] = []
    var isLoading: Bool = false
    var lastError: String?

    private init() {}

    func loadDashboard() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let openRows: [WhisperReportRow] = try await client
                .from("whisper_reports")
                .select()
                .eq("status", value: "open")
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            open = openRows

            let recentRows: [WhisperReportRow] = try await client
                .from("whisper_reports")
                .select()
                .in("status", values: ["helpful", "dismissed", "actioned"])
                .order("reviewed_at", ascending: false)
                .limit(50)
                .execute()
                .value
            recent = recentRows
        } catch {
            lastError = "Reports fetch failed (\(error.localizedDescription))"
        }
    }

    /// Marks a report as helpful. Increments the reporter's
    /// `helpful_report_count` so they progress toward the Guardian badge,
    /// then stamps the row with the moderator id.
    func markHelpful(_ row: WhisperReportRow, note: String? = nil) async -> Bool {
        let me = client.auth.currentUser?.id.uuidString
        do {
            // 1) Bump the reporter's counter (idempotent per-report because the
            //    row transitions out of `open` immediately after).
            if let reporter = row.reporter_id {
                _ = try? await client
                    .rpc("increment_helpful_report_count",
                         params: WhisperReporterRPCArgs(p_reporter: reporter))
                    .execute()
            }
            // 2) Resolve the report.
            try await client
                .from("whisper_reports")
                .update(WhisperReportStatusUpdate(
                    status: "helpful",
                    review_note: note,
                    reviewed_by: me,
                    reviewed_at: Date()
                ))
                .eq("id", value: row.id)
                .execute()
            // 3) The reporter's `helpful_report_count` cache will refresh on
            //    the next `preloadAgeBands` pass (feed scroll, profile open).
            await loadDashboard()
            return true
        } catch {
            lastError = "Mark helpful failed (\(error.localizedDescription))"
            return false
        }
    }

    func dismiss(_ row: WhisperReportRow, note: String? = nil) async -> Bool {
        let me = client.auth.currentUser?.id.uuidString
        do {
            try await client
                .from("whisper_reports")
                .update(WhisperReportStatusUpdate(
                    status: "dismissed",
                    review_note: note,
                    reviewed_by: me,
                    reviewed_at: Date()
                ))
                .eq("id", value: row.id)
                .execute()
            await loadDashboard()
            return true
        } catch {
            lastError = "Dismiss failed (\(error.localizedDescription))"
            return false
        }
    }

    func markActioned(_ row: WhisperReportRow, note: String? = nil) async -> Bool {
        let me = client.auth.currentUser?.id.uuidString
        do {
            try await client
                .from("whisper_reports")
                .update(WhisperReportStatusUpdate(
                    status: "actioned",
                    review_note: note,
                    reviewed_by: me,
                    reviewed_at: Date()
                ))
                .eq("id", value: row.id)
                .execute()
            await loadDashboard()
            return true
        } catch {
            lastError = "Update failed (\(error.localizedDescription))"
            return false
        }
    }
}
