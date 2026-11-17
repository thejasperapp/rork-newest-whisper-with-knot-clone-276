import Foundation
import SwiftUI
import Supabase

// MARK: - Schema
//
// Coaches don't edit Whisper data directly. Instead they write a *proposal*
// row that Whisper reads when the client opens a deep link
// (`jasper://coach-proposal/<id>`). Whisper renders a diff screen; on accept
// it applies the patch to its own tables and flips status to `accepted`.
//
// SQL the project owner must run once (idempotent):
//
// (The canonical migration lives in supabase/functions/whisper-push-fanout/
// migrations.sql — this comment is just a reference.)
//
//   create table if not exists public.whisper_coach_proposals (
//     id uuid primary key default gen_random_uuid(),
//     coach_user_id uuid not null,
//     client_user_id uuid not null,
//     kind text not null check (kind in (
//       'diet_plan','macros','workout','exercise_swap','note'
//     )),
//     target_id uuid,
//     patch jsonb not null default '{}'::jsonb,
//     note text,
//     status text not null default 'pending' check (status in (
//       'pending','accepted','declined','modified','expired'
//     )),
//     created_at  timestamptz not null default now(),
//     updated_at  timestamptz not null default now(),
//     responded_at timestamptz,
//     expires_at  timestamptz default now() + interval '7 days'
//   );
//
// Coach display name is read by joining public.profiles on
// coach_user_id (Whisper-side); we no longer denormalize it here.
//
//   create index if not exists whisper_coach_proposals_client_idx
//     on public.whisper_coach_proposals(client_user_id, status);
//   create index if not exists whisper_coach_proposals_coach_idx
//     on public.whisper_coach_proposals(coach_user_id, status);
//
//   alter table public.whisper_coach_proposals enable row level security;
//
//   drop policy if exists "coach insert proposal for accepted client"
//     on public.whisper_coach_proposals;
//   create policy "coach insert proposal for accepted client"
//     on public.whisper_coach_proposals for insert to authenticated
//     with check (
//       coach_user_id = auth.uid()
//       and exists (
//         select 1 from public.whisper_coach_requests r
//         where r.coach_user_id  = auth.uid()
//           and r.client_user_id = whisper_coach_proposals.client_user_id
//           and r.status = 'accepted'
//       )
//     );
//
//   drop policy if exists "coach read own proposals" on public.whisper_coach_proposals;
//   create policy "coach read own proposals"
//     on public.whisper_coach_proposals for select to authenticated
//     using (coach_user_id = auth.uid());
//
//   drop policy if exists "client read own proposals" on public.whisper_coach_proposals;
//   create policy "client read own proposals"
//     on public.whisper_coach_proposals for select to authenticated
//     using (client_user_id = auth.uid());
//
//   drop policy if exists "client respond own proposals" on public.whisper_coach_proposals;
//   create policy "client respond own proposals"
//     on public.whisper_coach_proposals for update to authenticated
//     using (client_user_id = auth.uid())
//     with check (client_user_id = auth.uid());

nonisolated struct WhisperCoachProposalRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let coach_user_id: String
    let client_user_id: String
    let kind: String
    let target_id: String?
    let patch: [String: JSONValue]?
    let note: String?
    let status: String
    let created_at: String?
    let updated_at: String?
    let responded_at: String?
}

/// Tiny JSON value used for the `patch` jsonb column. Codable wants a
/// concrete type and `[String: Any]` isn't Sendable.
nonisolated enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self)   { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b):   try c.encode(b)
        case .null:          try c.encodeNil()
        }
    }

    var doubleValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

private struct WhisperCoachProposalInsert: Encodable, Sendable {
    let coach_user_id: String
    let client_user_id: String
    let kind: String
    let target_id: String?
    let patch: [String: JSONValue]
    let note: String?
}

/// Coach-side service: create proposals and observe their status. One
/// instance per `WhisperClientHealthView` so the badge tracks that client.
@MainActor
@Observable
final class WhisperCoachProposalService {
    private let client = SupabaseService.shared.client

    /// Proposals the local coach has sent to one specific client.
    var proposals: [WhisperCoachProposalRow] = []
    private(set) var isSubmitting: Bool = false
    private(set) var lastError: String?

    /// Number of proposals still awaiting a client response.
    var pendingCount: Int { proposals.filter { $0.status == "pending" }.count }

    init() {}

    /// Returns true if the row was created. Caller is responsible for
    /// opening the Whisper deep link on success.
    @discardableResult
    func submit(
        clientUserID: String,
        kind: ProposalKind,
        targetID: String?,
        patch: [String: JSONValue],
        note: String?
    ) async -> WhisperCoachProposalRow? {
        isSubmitting = true
        defer { isSubmitting = false }

        let coachUID: String
        do {
            coachUID = try WhisperIdentityService.requireValidUID()
        } catch {
            lastError = error.localizedDescription
            print("[Whisper] proposal blocked — invalid coach UID: \(AccountStorage.currentUserID)")
            return nil
        }
        guard WhisperIdentityService.isValidSupabaseUID(clientUserID) else {
            lastError = "This client isn't linked to a Supabase account yet. Ask them to re-open Whisper and sign in."
            print("[Whisper] proposal blocked — invalid client UID: \(clientUserID)")
            return nil
        }

        let insert = WhisperCoachProposalInsert(
            coach_user_id: coachUID,
            client_user_id: clientUserID,
            kind: kind.rawValue,
            target_id: targetID,
            patch: patch,
            note: (note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? nil : note
        )

        do {
            let rows: [WhisperCoachProposalRow] = try await client
                .from("whisper_coach_proposals")
                .insert(insert)
                .select()
                .execute()
                .value
            if let row = rows.first {
                proposals.insert(row, at: 0)
                lastError = nil
                return row
            }
            lastError = "Proposal saved but no row returned"
            return nil
        } catch {
            let msg = error.localizedDescription
            if msg.lowercased().contains("relation") && msg.lowercased().contains("does not exist") {
                lastError = "Proposals table missing. Owner: run the whisper_coach_proposals SQL block once."
            } else {
                lastError = "Couldn't send suggestion: \(msg)"
            }
            print("[Whisper] coach proposal insert error: \(error)")
            return nil
        }
    }

    /// Pull proposals this coach has sent to the given client (any status).
    func refresh(forClient clientUserID: String) async {
        do {
            let rows: [WhisperCoachProposalRow] = try await client
                .from("whisper_coach_proposals")
                .select()
                .eq("coach_user_id", value: AccountStorage.currentUserID)
                .eq("client_user_id", value: clientUserID)
                .order("created_at", ascending: false)
                .limit(25)
                .execute()
                .value
            self.proposals = rows
        } catch {
            // Likely RLS or the table doesn't exist yet — keep current list.
            print("[Whisper] coach proposal fetch error: \(error.localizedDescription)")
        }
    }

    /// Re-send a previous proposal as a fresh row. Used when the original
    /// expired without a response, or was a no-op (e.g. created before the
    /// key-mismatch fix). Returns the newly created row.
    @discardableResult
    func resend(_ original: WhisperCoachProposalRow) async -> WhisperCoachProposalRow? {
        let kind = ProposalKind(rawValue: original.kind) ?? .note
        return await submit(
            clientUserID: original.client_user_id,
            kind: kind,
            targetID: original.target_id,
            patch: original.patch ?? [:],
            note: original.note
        )
    }

    /// Best-effort deep link into Whisper so the client can review + accept.
    /// Falls back to copying the link if Whisper isn't installed.
    static func openWhisperLink(for proposalID: String) {
        guard let url = URL(string: "jasper://coach-proposal/\(proposalID)") else { return }
        UIApplication.shared.open(url) { ok in
            if !ok {
                UIPasteboard.general.string = url.absoluteString
            }
        }
    }
}

nonisolated enum ProposalKind: String, CaseIterable, Sendable, Identifiable {
    var id: String { rawValue }

    case macros        = "macros"
    case dietPlan      = "diet_plan"
    case note          = "note"

    var title: String {
        switch self {
        case .macros:       return "Adjust macros"
        case .dietPlan:     return "Send program"
        case .note:         return "Send a note"
        }
    }

    var icon: String {
        switch self {
        case .macros:       return "scalemass"
        case .dietPlan:     return "leaf.fill"
        case .note:         return "text.bubble"
        }
    }
}
