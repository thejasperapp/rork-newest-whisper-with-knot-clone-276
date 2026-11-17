import SwiftUI
import Supabase

struct WhisperNotebookLiveTranscriptView: View {
    let meetingID: String
    let onChoose: (WhisperNotebookContext) -> Void
    @State private var rows: [WhisperNotebookSpeech] = []
    @State private var selected: Set<String> = []
    @State private var isExpanded: Bool = false
    @State private var isComplete: Bool = false
    @State private var errorText: String?
    @State private var refresh: UUID = UUID()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        DisclosureGroup("Live transcript · choose context", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Confirmed saved speech only, not provisional captions. Available speech may not cover everyone. Nothing is sent to Jasper until you choose an action.").font(.caption).foregroundStyle(.secondary)
                if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            Button {
                                if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: selected.contains(row.id) ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 4) { Text("\(row.username.isEmpty ? "Speaker" : row.username) · \(row.spoken_at)").font(.caption2.weight(.medium)); Text(row.text).font(.caption) }
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(row.id) ? .isSelected : [])
                        }
                    }
                }.frame(maxHeight: 210)
                if rows.isEmpty { Text("No confirmed speech yet. The meeting’s existing transcription must be enabled and permitted.").font(.caption).foregroundStyle(.secondary) }
                if !isComplete, !rows.isEmpty { Text("Showing the latest 200 passages. Earlier speech is not included; choose a smaller range.").font(.caption) }
                HStack {
                    Button("Use selected speech") { choose(all: false) }.disabled(!rows.contains { selected.contains($0.id) })
                    Button("Transcript so far") { choose(all: true) }.disabled(!isComplete || rows.isEmpty)
                }.font(.caption).frame(minHeight: 44)
                Button("Refresh saved speech") { refresh = UUID() }.font(.caption).frame(minHeight: 44)
            }.padding(.top, 10)
        }.font(.subheadline)
        .task(id: "\(meetingID):\(AccountStorage.generation):\(scenePhase):\(refresh)") {
            guard scenePhase == .active else { return }
            let owner = AccountStorage.currentUserID.lowercased(), generation = AccountStorage.generation
            while !Task.isCancelled {
                do {
                    let client = SupabaseService.shared.client
                    let session = try await client.auth.session
                    guard session.user.id.uuidString.lowercased() == owner else { return }
                    let speech: [WhisperNotebookSpeech] = try await client.from("whisper_meeting_transcripts").select("id,meeting_id,username,text,spoken_at").eq("meeting_id", value: meetingID).order("spoken_at", ascending: false).order("id", ascending: false).limit(201).execute().value
                    guard !Task.isCancelled, generation == AccountStorage.generation, owner == AccountStorage.currentUserID.lowercased() else { return }
                    rows = Array(speech.prefix(200).filter { $0.meeting_id.lowercased() == meetingID.lowercased() }.reversed())
                    isComplete = speech.count <= 200; errorText = nil
                } catch {
                    guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                    errorText = "Saved speech is unavailable or delayed. Reconnect and refresh; the call stays connected."
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
    private func choose(all: Bool) {
        let chosen = rows.filter { all || selected.contains($0.id) }
        var snapshot = WhisperNotebookDocument.blank(ownerID: AccountStorage.currentUserID.lowercased())
        snapshot.transcript = chosen.map { "[\($0.spoken_at)] \($0.username.isEmpty ? "Speaker" : $0.username): \($0.text)" }.joined(separator: "\n")
        do {
            let label = "\(all ? "Transcript so far" : "Chosen saved speech") · meeting \(meetingID) · through \(chosen.last?.spoken_at ?? "")"
            let sources = try snapshot.sources().map { source in WhisperNotebookDocument.Source(id: source.id, kind: source.kind, text: source.text, provenance: label) }
            onChoose(WhisperNotebookContext(sources: sources, label: label))
        } catch { errorText = error.localizedDescription }
    }
}
