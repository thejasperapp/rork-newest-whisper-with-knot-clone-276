import SwiftUI

struct WhisperRecordingArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var model: WhisperRecordingArchiveViewModel = WhisperRecordingArchiveViewModel()
    @State private var search: String = ""

    private var filtered: [WhisperRecordingArchive] {
        model.archives.filter { search.isEmpty || $0.title.localizedStandardContains(search) || $0.snapshot.transcript.contains { $0.text.localizedStandardContains(search) } || $0.snapshot.markers.contains { $0.title.localizedStandardContains(search) } }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("MEETING MEMORY", systemImage: "waveform").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(WhisperBrandGradient.rose)
                    Text("The conversation.\nStill here.").font(.largeTitle.bold())
                    Text("Private snapshots you explicitly backed up from a Whisper web meeting. Only your account can open them in the app; they are separate from shared recaps and device-only notes.").font(.subheadline).foregroundStyle(.secondary)
                    TextField("Search loaded recordings", text: $search).padding(14).background(WhisperTheme.card(colorScheme), in: Capsule())
                    if model.isLoading { ProgressView("Opening private archive…").frame(maxWidth: .infinity) }
                    if let error = model.errorText { Text(error).font(.footnote).foregroundStyle(.secondary); Button("Try again") { Task { await model.load() } }.frame(minHeight: 44) }
                    if !model.isLoading, model.errorText == nil, filtered.isEmpty { WhisperEmptyState(icon: "waveform", title: search.isEmpty ? "No cloud recordings here yet" : "No matching recordings", message: search.isEmpty ? "Record as the host on web, with everyone’s permission, then choose Save private cloud snapshot in Recordings. Older local-only recordings cannot be uploaded without cloud permission." : "Try a different search or load older recordings.", isCard: false) }
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { archive in
                            NavigationLink(value: archive.id) {
                                HStack(spacing: 12) {
                                    Image(systemName: archive.state == "ready" ? "play.fill" : "arrow.up.doc").frame(width: 44, height: 44).background(WhisperTheme.card(colorScheme), in: Circle())
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(archive.title).font(.headline).lineLimit(2)
                                        Text("\(WhisperRecordingArchive.time(archive.snapshot.duration)) · \(archive.state == "ready" ? "Private backup" : archive.state == "deleting" ? "Deletion incomplete" : "Upload incomplete")").font(.caption).foregroundStyle(.secondary)
                                        Text(String(archive.created_at.prefix(10))).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                }.padding(.vertical, 14).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider().overlay(WhisperTheme.hairline(colorScheme))
                        }
                    }
                    if model.canLoadMore { Button("Load older recordings") { Task { await model.load(more: true) } }.frame(minHeight: 44).disabled(model.isLoading) }
                    Text("iPhone opens saved web recordings; it does not record the complete call. Cloud playback needs a connection. No other-app calls or shared-screen sound are captured.").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 16).padding(.vertical, 20)
            }
            .scrollIndicators(.hidden).background(WhisperTheme.surface(colorScheme)).foregroundStyle(WhisperTheme.ink(colorScheme))
            .navigationTitle("Recordings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
            .navigationDestination(for: String.self) { id in
                if let archive = model.archives.first(where: { $0.id == id }) { WhisperRecordingArchivePlayerView(archive: archive) }
            }
            .task { await model.load() }
            .whisperRefreshable { await model.load() }
        }
        .onChange(of: AuthenticationService.shared.currentUser.userID) { _, _ in model.stop(); dismiss() }
        .tint(WhisperTheme.ink(colorScheme))
    }
}
