import Foundation

/// Presentation-only grouping. Documents and recording backups retain their original identities.
nonisolated struct WhisperNotebookGroup: Identifiable, Equatable {
    let id: String
    let meetingID: String?
    let standaloneID: String?
    var title: String
    var date: String
    var noteIDs: [String] = []
    var recordingIDs: Set<String> = []
    var preview: String = ""

    static func build(notes: [WhisperNotebookDocument], archives: [WhisperRecordingArchive]) -> [Self] {
        var groups: [String: Self] = [:]
        for note in notes {
            let key = note.meetingId.map { "meeting:\($0)" } ?? "entry:\(note.id)"
            var group = groups[key] ?? Self(id: key, meetingID: note.meetingId, standaloneID: note.meetingId == nil ? note.id : nil, title: note.displayTitle, date: note.createdAt)
            group.noteIDs.append(note.id)
            if group.preview.isEmpty { group.preview = String(note.notes.prefix(150)) }
            group.date = max(group.date, note.createdAt)
            groups[key] = group
        }
        for archive in archives {
            let key = archive.snapshot.meetingId.map { "meeting:\($0)" } ?? "entry:\(archive.recording_id)"
            var group = groups[key] ?? Self(id: key, meetingID: archive.snapshot.meetingId, standaloneID: archive.snapshot.meetingId == nil ? archive.recording_id : nil, title: archive.title, date: archive.created_at)
            if group.recordingIDs.isEmpty { group.title = archive.title }
            group.recordingIDs.insert(archive.recording_id)
            group.date = max(group.date, archive.created_at)
            groups[key] = group
        }
        return groups.values.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}
