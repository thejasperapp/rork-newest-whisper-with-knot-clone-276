import Foundation
import Supabase

@MainActor enum WhisperNotebookSyncService {
    private static var running: Set<String> = []
    private static var editors: [UUID: String] = [:]
    static let didSync = Notification.Name("WhisperNotebookSyncFinished")

    static func message(for error: Error) -> String {
        if let failure = error as? WhisperNotebookSyncFailure { return failure.message }
        if let database = error as? PostgrestError {
            switch database.code {
            case "42P01", "42883", "PGRST202", "PGRST205": return "Account saving isn't configured on the server yet. Your writing remains on this device; retry after setup is completed."
            case "42501", "PGRST301", "PGRST302", "28000": return "Your account couldn't authorize this save. Sign in again and retry."
            case "40001": return "Another device has newer edits. Finish editing and close the note, then retry; both versions will be kept."
            case "54000": return "Your account's note limit was reached. Free space before retrying this save."
            default: break
            }
        }
        return "Couldn't save to your account. Check your connection and retry; unsent changes remain on this device."
    }

    static func protect(editor: UUID, owner: String, id: String?) {
        editors[editor] = id.map { "\(owner):\($0)" }
    }

    nonisolated struct Save: Encodable, Sendable {
        let p_id: String
        let p_revision: Int
        let p_operation: String
        let p_document: WhisperNotebookDocument
        let p_deleted: Bool
    }

    static func sync(owner: String, assertCurrent: @MainActor () throws -> Void) async throws -> String {
        try assertCurrent(); try Task.checkCancellation()
        while running.contains(owner) {
            try await Task.sleep(for: .milliseconds(100))
            try assertCurrent(); try Task.checkCancellation()
        }
        running.insert(owner)
        defer {
            running.remove(owner)
            NotificationCenter.default.post(name: didSync, object: owner)
        }
        let client = SupabaseService.shared.client
        let session = try await client.auth.session
        try assertCurrent()
        guard session.user.id.uuidString.lowercased() == owner else { throw WhisperNotebookError.accountChanged }
        var cursor: String?
        var conflicts = 0
        var deferred = false
        while true {
            try assertCurrent(); try Task.checkCancellation()
            var query = client.from("whisper_private_notebooks").select().eq("owner_id", value: owner)
            if let cursor { query = query.gt("id", value: cursor) }
            let rows: [WhisperNotebookCloudRow] = try await query.order("id").limit(50).execute().value
            try assertCurrent(); try Task.checkCancellation()
            for row in rows {
                guard row.owner_id == owner else { throw WhisperNotebookError.accountChanged }
                if editors.values.contains("\(owner):\(row.id)") {
                    let stored = try WhisperNotebookStorage.load(ownerID: owner, includeDeleted: true).first { $0.id == row.id }
                    if let stored, stored.syncOperationId == row.operation_id { _ = try WhisperNotebookStorage.applyCloud(row, sent: stored) }
                    else if row.revision > (stored?.cloudRevision ?? 0) { deferred = true }
                    continue
                }
                conflicts += try WhisperNotebookStorage.applyCloud(row)
            }
            if rows.count < 50 { break }
            cursor = rows.last?.id
        }
        // Enroll existing writing only after remote edits and tombstones are reconciled.
        for var entry in try WhisperNotebookStorage.load(ownerID: owner) where entry.syncEnabled != true && !editors.values.contains("\(owner):\(entry.id)") {
            try assertCurrent(); try Task.checkCancellation()
            entry.syncEnabled = true
            _ = try WhisperNotebookStorage.save(entry)
        }
        let entries = try WhisperNotebookStorage.load(ownerID: owner, includeDeleted: true)
        let pending = entries.filter { $0.syncEnabled == true && $0.syncedStorageRevision != $0.storageRevision }
        let ordered = pending.filter { $0.deletedAt != nil } + pending.filter { $0.deletedAt == nil }
        var failures: [String] = []
        for entry in ordered {
            try assertCurrent(); try Task.checkCancellation()
            do {
                guard let operation = entry.syncOperationId else { throw WhisperNotebookError.storage }
                let row: WhisperNotebookCloudRow = try await client.rpc("save_private_notebook", params: Save(p_id: entry.id, p_revision: entry.cloudRevision ?? 0, p_operation: operation, p_document: entry, p_deleted: entry.deletedAt != nil)).execute().value
                try assertCurrent(); try Task.checkCancellation()
                _ = try WhisperNotebookStorage.applyCloud(row, sent: entry)
            } catch {
                try assertCurrent(); try Task.checkCancellation()
                failures.append(message(for: error))
            }
        }
        if let first = failures.first { throw WhisperNotebookSyncFailure(message: "\(failures.count) note(s) need attention. \(first)") }
        return conflicts > 0 ? "Synced. Conflicting edits are in Unsaved writing found; recover to keep both." : deferred ? "Newer edits available · finish editing and close the note to receive them" : "Account sync up to date"
    }
}
