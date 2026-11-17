import Foundation

/// A flat index of notes plus unlinked original recordings. Never groups or merges writing.
nonisolated struct WhisperNotebookEntry: Identifiable, Sendable {
    let id: String
    let title: String
    let preview: String
    let date: String
    let meetingID: String?
    let note: WhisperNotebookDocument?
    let archive: WhisperRecordingArchive?

    static func build(notes: [WhisperNotebookDocument], archives: [WhisperRecordingArchive], query: String, folder: String, recordingsOnly: Bool = false) -> [Self] {
        let recordings = Dictionary(grouping: archives, by: \.recording_id)
        let ids = Set(notes.flatMap { [$0.id] + ($0.recordingIds ?? []) })
        var entries = notes.filter { note in
            !recordingsOnly && (folder.isEmpty || note.folder == folder) && (query.isEmpty || [note.title, note.notes, note.transcript, note.people, note.folder].contains { $0.localizedStandardContains(query) })
        }.map { note in
            Self(id: note.id, title: note.displayTitle, preview: note.notes.isEmpty ? "Start writing…" : note.notes, date: note.createdAt, meetingID: note.meetingId, note: note, archive: (note.recordingIds ?? [note.id]).compactMap { recordings[$0]?.first }.first)
        }
        if folder.isEmpty || recordingsOnly {
            for (id, copies) in recordings where recordingsOnly || !ids.contains(id) {
                guard let archive = copies.first, query.isEmpty || archive.title.localizedStandardContains(query) || archive.snapshot.transcript.contains(where: { $0.text.localizedStandardContains(query) }) else { continue }
                entries.append(Self(id: id, title: archive.title, preview: "Recording only · playback needs no note", date: archive.created_at, meetingID: archive.snapshot.meetingId, note: nil, archive: archive))
            }
        }
        return entries.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}
