import Foundation
import Observation
import Supabase

/// Finalized speech is retained before upload and removed only after a verified insert.
@MainActor @Observable final class WhisperTranscriptOutbox {
    static let shared = WhisperTranscriptOutbox()
    private(set) var errorText: String?
    private(set) var pendingCount: Int = 0
    private var activeOwner: String = ""
    private var pending: [WhisperPendingSpeech] = []
    private var task: Task<Void, Never>?
    private init() {}

    private func file(_ owner: String) throws -> URL {
        guard UUID(uuidString: owner) != nil else { throw WhisperNotebookError.accountChanged }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("WhisperTranscriptOutbox", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(owner).json")
    }
    private func load(_ owner: String) throws {
        guard activeOwner != owner else { return }
        let location = try file(owner)
        let loaded = FileManager.default.fileExists(atPath: location.path) ? try JSONDecoder().decode([WhisperPendingSpeech].self, from: Data(contentsOf: location)) : []
        guard loaded.allSatisfy({ $0.user_id == owner }) else { throw WhisperNotebookError.accountChanged }
        activeOwner = owner; pending = loaded; pendingCount = loaded.count; errorText = nil
    }
    private func persist() throws { try JSONEncoder().encode(pending).write(to: file(activeOwner), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); pendingCount = pending.count }
    @discardableResult func enqueue(meetingID: String, text: String, spokenAt: Date = Date()) -> String? {
        let owner = AccountStorage.currentUserID.lowercased()
        guard SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == owner else { return nil }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty else { return nil }
        do {
            try load(owner)
            guard pending.count < 5000 else { errorText = "Transcript recovery storage is full. Retry saving before continuing."; return nil }
            let entry = WhisperPendingSpeech(id: UUID().uuidString.lowercased(), meeting_id: meetingID.lowercased(), user_id: owner, username: LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username ?? "speaker", text: clean, spoken_at: spokenAt.ISO8601Format(.iso8601(timeZone: .gmt).year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: true).timeSeparator(.colon)))
            pending.append(entry)
            do { try persist() } catch { errorText = "Speech is waiting in memory; device recovery could not be saved. Keep the meeting open and retry." }
            Task { await self.flush() }
            return entry.id
        } catch { errorText = "Transcript recovery could not be opened. Existing recovery data was not overwritten."; return nil }
    }
    func flush() async {
        if let task { await task.value; return }
        let owner = AccountStorage.currentUserID.lowercased()
        guard SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == owner else { return }
        do { try load(owner) } catch { errorText = "Transcript recovery could not load. Please retry."; return }
        let generation = AccountStorage.generation
        let work = Task { await self.drain(owner: owner, generation: generation) }
        task = work; await work.value; task = nil
    }
    private func drain(owner: String, generation: UUID) async {
        let client = SupabaseService.shared.client
        var attempted: Set<String> = []
        while let entry = pending.first(where: { !attempted.contains($0.id) }) {
            attempted.insert(entry.id)
            guard !Task.isCancelled, AccountStorage.generation == generation, AccountStorage.currentUserID.lowercased() == owner, activeOwner == owner else { return }
            do {
                do { try await client.from("whisper_meeting_transcripts").insert(entry).execute() }
                catch let failure as PostgrestError where failure.code == "23505" {
                    let rows: [WhisperPendingSpeech] = try await client.from("whisper_meeting_transcripts").select("id,meeting_id,user_id,username,text,spoken_at").eq("id", value: entry.id).eq("user_id", value: owner).limit(1).execute().value
                    guard let saved = rows.first, saved.meeting_id == entry.meeting_id, saved.text == entry.text else { throw WhisperNotebookError.conflict }
                }
                guard AccountStorage.generation == generation, activeOwner == owner else { return }
                pending.removeAll { $0.id == entry.id }; try persist()
            } catch {
                guard activeOwner == owner else { return }
                errorText = "Some captured speech is waiting to save. Reconnect and tap Refresh transcript. Your retained speech will be retried."
            }
        }
        if pending.isEmpty { errorText = nil }
        else { pendingCount = pending.count }
    }
}
