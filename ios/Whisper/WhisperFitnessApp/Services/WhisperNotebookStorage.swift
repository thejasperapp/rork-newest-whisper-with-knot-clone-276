import Foundation

/// Files are account-scoped, protected while locked, and excluded from device backups.
nonisolated enum WhisperNotebookStorage {
    private static func directory(ownerID: String) throws -> URL {
        guard let owner = UUID(uuidString: ownerID) else { throw WhisperNotebookError.accountChanged }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var directory = root.appendingPathComponent("PersonalNotebooks", isDirectory: true).appendingPathComponent(owner.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory
    }

    private static func file(ownerID: String, id: String) throws -> URL {
        guard let id = UUID(uuidString: id) else { throw WhisperNotebookError.storage }
        return try directory(ownerID: ownerID).appendingPathComponent(id.uuidString.lowercased()).appendingPathExtension("json")
    }

    static func load(ownerID: String, includeDeleted: Bool = false) throws -> [WhisperNotebookDocument] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory(ownerID: ownerID), includingPropertiesForKeys: [.fileSizeKey]).filter { $0.pathExtension == "json" }
        return try urls.map { url in
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else { throw WhisperNotebookError.storage }
            let document = try JSONDecoder().decode(WhisperNotebookDocument.self, from: Data(contentsOf: url))
            guard document.ownerId == ownerID, document.version == 1 else { throw WhisperNotebookError.storage }
            return document
        }.filter { includeDeleted || $0.deletedAt == nil }.sorted { $0.updatedAt > $1.updatedAt }
    }

    @MainActor static func save(_ input: WhisperNotebookDocument) throws -> WhisperNotebookDocument {
        let url = try file(ownerID: input.ownerId, id: input.id)
        var previousRevision = 0
        var saved = input
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try JSONDecoder().decode(WhisperNotebookDocument.self, from: Data(contentsOf: url))
            guard previous.ownerId == input.ownerId else { throw WhisperNotebookError.accountChanged }
            guard previous.deletedAt == nil else { throw WhisperNotebookError.conflict }
            previousRevision = previous.storageRevision
            saved.cloudRevision = previous.cloudRevision
            saved.syncedStorageRevision = previous.syncedStorageRevision
            saved.syncEnabled = previous.syncEnabled == true || input.syncEnabled == true
        } else if try load(ownerID: input.ownerId).count >= 200 {
            throw WhisperNotebookError.limit
        }
        guard input.storageRevision == previousRevision else { throw WhisperNotebookError.conflict }
        saved.syncOperationId = UUID().uuidString.lowercased()
        saved.storageRevision += 1
        saved.updatedAt = Date().ISO8601Format()
        guard (saved.highlights?.count ?? 0) <= 100, saved.highlights?.allSatisfy(\.isValid) ?? true else { throw WhisperNotebookError.limit }
        let data = try JSONEncoder().encode(saved)
        guard data.count <= 2_000_000 else { throw WhisperNotebookError.limit }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return saved
    }

    /// A recording and its personal note share a stable UUID on web and iPhone, not editable text links.
    @MainActor static func recordingNote(_ archive: WhisperRecordingArchive) throws -> WhisperNotebookDocument {
        guard archive.isValid, archive.state == "ready" else { throw WhisperNotebookError.storage }
        let id = archive.recording_id.lowercased()
        if let existing = try load(ownerID: archive.owner_id, includeDeleted: true).first(where: { $0.id == id }) {
            guard existing.deletedAt == nil, existing.meetingId == archive.snapshot.meetingId else { throw WhisperNotebookError.conflict }
            return existing
        }
        return try save(.blank(ownerID: archive.owner_id, meetingID: archive.snapshot.meetingId, title: archive.title, id: id))
    }

    @MainActor static func delete(_ document: WhisperNotebookDocument) throws {
        let url = try file(ownerID: document.ownerId, id: document.id)
        let current = try JSONDecoder().decode(WhisperNotebookDocument.self, from: Data(contentsOf: url))
        guard current.ownerId == document.ownerId, current.storageRevision == document.storageRevision else { throw WhisperNotebookError.conflict }
        do {
            var tombstone = current
            tombstone.title = ""; tombstone.folder = ""; tombstone.people = ""; tombstone.instructions = ""
            tombstone.notes = ""; tombstone.transcript = ""; tombstone.enhancement = nil; tombstone.commitments = []; tombstone.highlights = []
            tombstone.deletedAt = Date().ISO8601Format()
            tombstone.syncOperationId = UUID().uuidString.lowercased()
            tombstone.storageRevision += 1
            try JSONEncoder().encode(tombstone).write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    /// Called on the main actor alongside editor saves; never replaces concurrent local writing.
    @MainActor static func applyCloud(_ row: WhisperNotebookCloudRow, sent: WhisperNotebookDocument? = nil) throws -> Int {
        guard row.revision > 0, row.deleted == (row.document == nil),
              row.document == nil || (row.document?.ownerId == row.owner_id && row.document?.id == row.id) else { throw WhisperNotebookError.storage }
        let url = try file(ownerID: row.owner_id, id: row.id)
        let current: WhisperNotebookDocument? = FileManager.default.fileExists(atPath: url.path) ? try JSONDecoder().decode(WhisperNotebookDocument.self, from: Data(contentsOf: url)) : nil
        if (current?.cloudRevision ?? 0) > row.revision { return 0 }
        if let sent {
            guard sent.ownerId == row.owner_id, sent.id == row.id, sent.syncOperationId == row.operation_id else { throw WhisperNotebookError.accountChanged }
            guard var current else { return 0 }
            current.cloudRevision = row.revision
            current.syncedStorageRevision = sent.storageRevision
            try JSONEncoder().encode(current).write(to: url, options: [.atomic, .completeFileProtection])
            return 0
        }
        if let current, current.cloudRevision == row.revision { return 0 }
        if var current, current.syncOperationId == row.operation_id {
            current.cloudRevision = row.revision; current.syncedStorageRevision = current.storageRevision
            try JSONEncoder().encode(current).write(to: url, options: [.atomic, .completeFileProtection]); return 0
        }
        if var current, current.deletedAt != nil, current.syncedStorageRevision != current.storageRevision, let remote = row.document {
            try retainRecovery(remote.newCopy(prefix: "Remote edits · "), editorID: UUID())
            current.cloudRevision = row.revision
            try JSONEncoder().encode(current).write(to: url, options: [.atomic, .completeFileProtection])
            return 1
        }
        var conflicts = 0
        if let current, current.deletedAt == nil, current.syncedStorageRevision != current.storageRevision {
            // Recovery is committed before adopting the remote version. If it fails, stop.
            try retainRecovery(current, editorID: UUID(uuidString: current.syncOperationId ?? "") ?? UUID())
            conflicts = 1
        }
        let placeholder = WhisperNotebookDocument.blank(ownerID: row.owner_id, id: row.id)
        var next = row.document ?? current ?? placeholder
        next.storageRevision = (current?.storageRevision ?? 0) + 1
        next.syncEnabled = true; next.cloudRevision = row.revision
        next.syncedStorageRevision = next.storageRevision; next.syncOperationId = row.operation_id
        next.deletedAt = row.deleted ? row.updated_at : nil
        if row.deleted { next.title = ""; next.folder = ""; next.people = ""; next.instructions = ""; next.notes = ""; next.transcript = ""; next.enhancement = nil; next.commitments = []; next.highlights = [] }
        let data = try JSONEncoder().encode(next)
        guard data.count <= 2_000_000 else { throw WhisperNotebookError.limit }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return conflicts
    }

    static func retainRecovery(_ document: WhisperNotebookDocument, editorID: UUID) throws {
        let key = "\(editorID.uuidString)-\(document.id)"
        let url = try directory(ownerID: document.ownerId).appendingPathComponent(key).appendingPathExtension("draft")
        try JSONEncoder().encode(document).write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func clearRecovery(ownerID: String, key: String) throws {
        guard key.count == 73, key.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { throw WhisperNotebookError.storage }
        let url = try directory(ownerID: ownerID).appendingPathComponent(key).appendingPathExtension("draft")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    static func recoveries(ownerID: String) throws -> [WhisperNotebookDocument.Recovery] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory(ownerID: ownerID), includingPropertiesForKeys: [.fileSizeKey]).filter { $0.pathExtension == "draft" }
        return try urls.map { url in
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else { throw WhisperNotebookError.storage }
            let document = try JSONDecoder().decode(WhisperNotebookDocument.self, from: Data(contentsOf: url))
            guard document.ownerId == ownerID else { throw WhisperNotebookError.storage }
            return .init(id: url.deletingPathExtension().lastPathComponent, document: document)
        }
    }
}
