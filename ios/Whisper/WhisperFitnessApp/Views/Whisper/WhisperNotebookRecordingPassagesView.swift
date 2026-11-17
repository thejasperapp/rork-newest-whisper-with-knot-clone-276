import SwiftUI

struct WhisperNotebookRecordingPassagesView: View {
    let archive: WhisperRecordingArchive
    let onChoose: (WhisperNotebookContext) -> Void
    @State private var selected: Set<String> = []
    @State private var count: Int = 50
    @State private var errorText: String?
    var body: some View {
        DisclosureGroup("Choose recording passages for Jasper") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Only selected transcript passages are used. No audio or video is sent.").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(archive.snapshot.transcript.prefix(count))) { passage in
                            Button {
                                if selected.contains(passage.id) { selected.remove(passage.id) } else { selected.insert(passage.id) }
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: selected.contains(passage.id) ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(WhisperRecordingArchive.time(passage.start))–\(WhisperRecordingArchive.time(passage.end))\(passage.timing == "chunk" ? " · approximate" : "")").font(.caption2)
                                        Text(passage.text).font(.caption)
                                    }
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(passage.id) ? .isSelected : [])
                        }
                    }
                }.frame(maxHeight: 210)
                if count < archive.snapshot.transcript.count { Button("More transcript passages") { count += 50 }.frame(minHeight: 44) }
                Button("Use these passages as context") { choose() }.frame(minHeight: 44).disabled(selected.isEmpty)
                if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
                if archive.snapshot.transcript.isEmpty { Text("No saved transcript for this recording. Playback stays available.").font(.caption).foregroundStyle(.secondary) }
            }.padding(.top, 8)
        }.font(.caption)
    }
    private func choose() {
        let passages = archive.snapshot.transcript.filter { selected.contains($0.id) }
        var note = WhisperNotebookDocument.blank(ownerID: archive.owner_id)
        note.transcript = passages.map { "[\(WhisperRecordingArchive.time($0.start))–\(WhisperRecordingArchive.time($0.end))\($0.timing == "chunk" ? "; approximate range" : "")] \($0.text)" }.joined(separator: "\n")
        do {
            let label = "Recording \(archive.title) · \(archive.recording_id) · revision \(archive.source_revision) · \(passages.count) selected passages"
            let sources = try note.sources().map { source in WhisperNotebookDocument.Source(id: source.id, kind: source.kind, text: source.text, provenance: label) }
            onChoose(.init(sources: sources, label: label))
        }
        catch { errorText = error.localizedDescription }
    }
}
