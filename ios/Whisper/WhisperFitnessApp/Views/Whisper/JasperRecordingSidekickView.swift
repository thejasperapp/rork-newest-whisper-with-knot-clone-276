import SwiftUI

struct JasperRecordingSidekickView: View {
    let archive: WhisperRecordingArchive
    let passages: [WhisperRecordingArchive.Passage]
    let onSeek: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model: JasperMeetingsViewModel = JasperMeetingsViewModel()
    private var context: [String: Any] {
        ["id": archive.recording_id, "title": archive.title, "revision": archive.source_revision,
         "passages": passages.map { ["id": $0.id, "start": $0.start, "end": $0.end, "text": $0.text, "timing": $0.timing, "speakerName": $0.speakerName ?? ""] as [String: Any] }]
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                JasperMeetingAssistantView(model: model, meetingID: archive.snapshot.meetingId, recordingContext: context, onSeekRecording: { id, seconds in if id == archive.recording_id { onSeek(seconds) } })
                    .padding(.horizontal, 20).padding(.vertical, 16)
            }.navigationTitle("Recording sidekick").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
