import Foundation

/// Frozen context explicitly chosen for a private meeting-sidekick request.
nonisolated struct WhisperSidekickFile: Identifiable, Sendable {
    let id: String
    let title: String
    let sources: [WhisperNotebookDocument.Source]

    static func note(_ note: WhisperNotebookDocument) throws -> Self {
        Self(id: "note:\(note.id)", title: note.displayTitle, sources: try note.sources().map {
            .init(id: $0.id, kind: $0.kind, text: $0.text, provenance: "\(note.displayTitle) · note \(note.id) · revision \(note.storageRevision) · \(note.updatedAt)")
        })
    }

    static func speech(meetingID: String, title: String, rows: [WhisperNotebookSpeech], label: String, owner: String) throws -> Self {
        var document = WhisperNotebookDocument.blank(ownerID: owner)
        document.transcript = rows.map { "[\($0.spoken_at)] \($0.username.isEmpty ? "Speaker" : $0.username): \($0.text)" }.joined(separator: "\n")
        let provenance = "\(title.prefix(160)) · meeting \(meetingID) · \(label) · through \(rows.last?.spoken_at ?? "no speech")"
        return Self(id: "meeting:\(meetingID)", title: title, sources: try document.sources().map {
            .init(id: $0.id, kind: $0.kind, text: $0.text, provenance: provenance)
        })
    }

    static func combine(_ files: [Self]) throws -> [WhisperNotebookDocument.Source] {
        guard !files.isEmpty, files.count <= 8, Set(files.map(\.id)).count == files.count else { throw WhisperNotebookError.tooLong }
        let sources = files.enumerated().flatMap { index, file in
            file.sources.map { WhisperNotebookDocument.Source(id: "M\(index + 1)-\($0.id)", kind: $0.kind, text: $0.text, provenance: $0.provenance) }
        }
        guard !sources.isEmpty, sources.count <= 160, sources.reduce(0, { $0 + $1.text.utf16.count }) <= 24000 else { throw WhisperNotebookError.tooLong }
        return sources
    }
}
