import Foundation
import Supabase

// MARK: - Schema
//
// Lightweight client-side receipt for v2 coach proposals (macros / diet_plan
// / exercise_swap / note). The proposal itself lives inside the chat embed,
// so the receipt is the only durable record of accept/decline. Coaches read
// from this table when they want a "did they apply it?" indicator.
//
// SQL the project owner must run once (idempotent):
//
//   create table if not exists public.whisper_proposal_receipts (
//     proposal_id uuid not null,
//     client_user_id uuid not null,
//     status text not null check (status in ('accepted','declined')),
//     responded_at timestamptz not null default now(),
//     message_id uuid,
//     primary key (proposal_id, client_user_id)
//   );
//
//   alter table public.whisper_proposal_receipts enable row level security;
//
//   drop policy if exists "client writes own receipts"
//     on public.whisper_proposal_receipts;
//   create policy "client writes own receipts"
//     on public.whisper_proposal_receipts for insert to authenticated
//     with check (client_user_id = auth.uid());
//
//   drop policy if exists "client updates own receipts"
//     on public.whisper_proposal_receipts;
//   create policy "client updates own receipts"
//     on public.whisper_proposal_receipts for update to authenticated
//     using (client_user_id = auth.uid())
//     with check (client_user_id = auth.uid());
//
//   drop policy if exists "client reads own receipts"
//     on public.whisper_proposal_receipts;
//   create policy "client reads own receipts"
//     on public.whisper_proposal_receipts for select to authenticated
//     using (client_user_id = auth.uid());
//
//   drop policy if exists "coach reads receipts for accepted clients"
//     on public.whisper_proposal_receipts;
//   create policy "coach reads receipts for accepted clients"
//     on public.whisper_proposal_receipts for select to authenticated
//     using (
//       exists (
//         select 1 from public.whisper_coach_requests r
//         where r.coach_user_id  = auth.uid()
//           and r.client_user_id = whisper_proposal_receipts.client_user_id
//           and r.status = 'accepted'
//       )
//     );

/// Client-side accept/decline ledger for v2 coach proposals. Writes are
/// idempotent (upsert on the composite primary key) so retries and double-
/// taps don't create duplicate rows.
@MainActor
@Observable
final class WhisperProposalReceiptService {
    static let shared = WhisperProposalReceiptService()

    private let client = SupabaseService.shared.client
    private init() {}

    /// Records the client's response to a v2 coach proposal. Returns true
    /// on success; false on RLS / missing-table errors (non-fatal — the
    /// embed already lives in the DM as a permanent record).
    @discardableResult
    func record(proposalID: String, status: String, messageID: String? = nil) async -> Bool {
        let uid = AccountStorage.currentUserID
        guard WhisperIdentityService.isValidSupabaseUID(uid) else {
            print("[Whisper] receipt skipped — invalid client UID")
            return false
        }
        struct Row: Encodable {
            let proposal_id: String
            let client_user_id: String
            let status: String
            let responded_at: String
            let message_id: String?
        }
        let row = Row(
            proposal_id: proposalID,
            client_user_id: uid,
            status: status,
            responded_at: ISO8601DateFormatter().string(from: Date()),
            message_id: messageID
        )
        do {
            try await client
                .from("whisper_proposal_receipts")
                .upsert(row, onConflict: "proposal_id,client_user_id")
                .execute()
            return true
        } catch {
            print("[Whisper] receipt write failed: \(error.localizedDescription)")
            return false
        }
    }
}

/// Single receipt row, used by coach surfaces that want to show whether a
/// client accepted/declined a proposal sent via v2 embed.
nonisolated struct WhisperProposalReceiptRow: Codable, Sendable, Hashable {
    let proposal_id: String
    let client_user_id: String
    let status: String
    let responded_at: String?
    let message_id: String?
}

extension WhisperProposalReceiptService {
    /// Fetches receipts for a batch of proposal IDs. Used by the coach-side
    /// proposal lists to attach status pills without changing schema.
    func fetch(proposalIDs: [String]) async -> [String: WhisperProposalReceiptRow] {
        guard !proposalIDs.isEmpty else { return [:] }
        do {
            let rows: [WhisperProposalReceiptRow] = try await client
                .from("whisper_proposal_receipts")
                .select()
                .in("proposal_id", values: proposalIDs)
                .execute()
                .value
            var byID: [String: WhisperProposalReceiptRow] = [:]
            for row in rows { byID[row.proposal_id] = row }
            return byID
        } catch {
            print("[Whisper] receipt fetch failed: \(error.localizedDescription)")
            return [:]
        }
    }
}
