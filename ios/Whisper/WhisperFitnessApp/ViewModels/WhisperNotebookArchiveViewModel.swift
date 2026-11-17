import Foundation
import Observation
import Supabase

/// Reads the account's meeting-generated archive without joining rooms or changing shared notes.
@MainActor @Observable
final class WhisperNotebookArchiveViewModel {
    private(set) var meetings: [WhisperMeetingRow] = []
    private(set) var isLoading: Bool = false
    private(set) var canLoadMore: Bool = true
    var errorText: String?
    private var page: Int = 0
    private let owner: String = AccountStorage.currentUserID.lowercased()
    private let generation: UUID = AccountStorage.generation
    private let client = SupabaseService.shared.client

    var isCurrent: Bool {
        AuthenticationService.shared.isSignedIn && generation == AccountStorage.generation && owner == AccountStorage.currentUserID.lowercased() && client.auth.currentUser?.id.uuidString.lowercased() == owner
    }

    private func check() throws {
        try Task.checkCancellation()
        guard isCurrent else { throw WhisperNotebookError.accountChanged }
    }

    nonisolated private struct Participation: Decodable, Sendable { let meeting_id: String }

    func load(more: Bool = false, meetingID: String? = nil, includeWithoutSummary: Bool = false) async {
        guard !isLoading, isCurrent else { return }
        isLoading = true; errorText = nil
        defer { isLoading = false }
        let nextPage = more ? page + 1 : 0
        do {
            async let hosted: [WhisperMeetingRow] = client.from("whisper_meetings").select().eq("host_id", value: owner).order("created_at", ascending: false).order("id").range(from: nextPage * 30, to: nextPage * 30 + 29).execute().value
            async let joined: [Participation] = client.from("whisper_meeting_participants").select("meeting_id").eq("user_id", value: owner).order("joined_at", ascending: false).order("meeting_id").range(from: nextPage * 30, to: nextPage * 30 + 29).execute().value
            var rows = try await hosted
            let participated = try await joined
            try check()
            let hasMore = rows.count == 30 || participated.count == 30
            let ids = participated.map(\.meeting_id).filter { id in !rows.contains { $0.id == id } }
            if !ids.isEmpty {
                let extra: [WhisperMeetingRow] = try await client.from("whisper_meetings").select().in("id", values: ids).execute().value
                rows += extra
            }
            if !more, let meetingID, !rows.contains(where: { $0.id == meetingID }) {
                let linked: [WhisperMeetingRow] = try await client.from("whisper_meetings").select().eq("id", value: meetingID).limit(1).execute().value
                rows += linked
            }
            try check()
            var seen: Set<String> = []
            meetings = ((more ? meetings : []) + rows).filter { (includeWithoutSummary || !($0.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && seen.insert($0.id).inserted }.sorted {
                if ($0.id == meetingID) != ($1.id == meetingID) { return $0.id == meetingID }
                return ($0.ended_at ?? $0.created_at ?? "") > ($1.ended_at ?? $1.created_at ?? "")
            }
            page = nextPage; canLoadMore = hasMore
        } catch {
            guard isCurrent, !Task.isCancelled else { meetings = []; return }
            errorText = "Couldn't load your notes archive. Please retry."
        }
    }
}
