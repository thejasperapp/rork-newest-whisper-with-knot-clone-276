import Foundation
import Observation
import Supabase

/// Searches permitted, loaded pages on device. No search text or results go to AI.
@MainActor @Observable final class WorkspaceSearchViewModel {
    let owner: String = AccountStorage.currentUserID.lowercased()
    private let generation: UUID = AccountStorage.generation
    let meetings: WhisperNotebookArchiveViewModel = WhisperNotebookArchiveViewModel()
    let recordings: WhisperRecordingArchiveViewModel = WhisperRecordingArchiveViewModel()
    let work: WorkspaceWorkViewModel = WorkspaceWorkViewModel()
    var notes: [WhisperNotebookDocument] = []
    var people: [WhisperRecruiterService.ProspectRow] = []
    var errorText: String?
    var peopleMore: Bool = true
    var loadingPeople: Bool = false
    private var peoplePage: Int = -1
    private var peopleOperation: UUID = UUID()
    private var isLoading: Bool = false
    var isCurrent: Bool { generation == AccountStorage.generation && owner == AccountStorage.currentUserID.lowercased() && meetings.isCurrent }
    var results: [WorkspaceSearchResult] {
        guard isCurrent else { return [] }
        var rows = meetings.meetings.map { WorkspaceSearchResult(objectID: $0.id, kind: "Meetings", title: $0.title, text: $0.summary ?? "", date: $0.created_at ?? "") }
        rows += notes.map { .init(objectID: $0.id, kind: "Notes", title: $0.displayTitle, text: $0.notes + " " + $0.transcript + " " + $0.people, date: $0.updatedAt) }
        rows += recordings.archives.map { .init(objectID: $0.id, kind: "Recordings", title: $0.title, text: $0.snapshot.transcript.map(\.text).joined(separator: " "), date: $0.created_at) }
        rows += people.map { .init(objectID: $0.id, kind: "People", title: $0.prospect_display_name ?? $0.prospect_username ?? "Person", text: [$0.prospect_username, $0.niche, $0.suggested_role, $0.status].compactMap { $0 }.joined(separator: " "), date: $0.updated_at ?? "") }
        rows += (work.board?.items ?? []).map { .init(objectID: $0.id, kind: "Work", title: $0.title, text: "\($0.kind) \($0.status) \($0.deadline)", date: $0.updatedAt) }
        return rows.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    func load() async {
        guard isCurrent, !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        peopleOperation = UUID(); loadingPeople = false
        notes = []; people = []; errorText = nil; peoplePage = -1
        do { notes = try WhisperNotebookStorage.load(ownerID: owner) }
        catch { errorText = "Private writing couldn’t load. Pull to retry." }
        async let meetingLoad: Void = meetings.load(includeWithoutSummary: true)
        async let recordingLoad: Void = recordings.load()
        async let peopleLoad: Void = loadPeople()
        async let workLoad: Void = work.load()
        async let teamsLoad: Void = work.loadTeams()
        _ = await (meetingLoad, recordingLoad, peopleLoad, workLoad, teamsLoad)
        if !isCurrent { clear() }
    }
    func loadPeople() async {
        guard isCurrent, !loadingPeople else { return }
        let token = UUID(); peopleOperation = token
        loadingPeople = true; defer { if token == peopleOperation { loadingPeople = false } }
        let page = peoplePage + 1
        do {
            let rows: [WhisperRecruiterService.ProspectRow] = try await SupabaseService.shared.client.from("whisper_recruiter_prospects").select().eq("recruiter_id", value: owner).order("updated_at", ascending: false).order("id").range(from: page * 50, to: page * 50 + 49).execute().value
            guard isCurrent, token == peopleOperation, !Task.isCancelled else { return }
            var seen = Set(people.map(\.id))
            people += rows.filter { $0.recruiter_id.lowercased() == owner && seen.insert($0.id).inserted }
            peopleMore = rows.count == 50; peoplePage = page
        } catch { if isCurrent, token == peopleOperation, !Task.isCancelled { errorText = "People couldn’t load. Retry to search further." } }
    }
    func clear() { peopleOperation = UUID(); notes = []; people = []; work.clear(); recordings.stop() }
}
