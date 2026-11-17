import SwiftUI
import AVKit

struct WhisperRecordingArchivePlayerView: View {
    let archive: WhisperRecordingArchive
    var onClose: (() -> Void)? = nil
    var onImportTranscript: ((String) -> Void)? = nil
    var isEmbedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: WhisperRecordingArchiveViewModel = WhisperRecordingArchiveViewModel()
    @State private var audioOnly: Bool = false
    @State private var confirmDelete: Bool = false
    @State private var detailsOpen: Bool = false
    @State private var openTask: Task<Void, Never>?
    @State private var deletionTask: Task<Void, Never>?
    @State private var jasperPassages: [WhisperRecordingArchive.Passage] = []
    @State private var showsJasper: Bool = false

    var body: some View {
        WhisperNotebookContentContainer(isInline: onClose != nil) {
            if model.isCurrent {
            VStack(alignment: .leading, spacing: 18) {
                if !isEmbedded { Text(archive.title).font(.headline) }
                if archive.state == "ready" {
                    if model.isOpening { ProgressView("Opening private playback…").frame(maxWidth: .infinity).padding(.vertical, 30) }
                    if let url = model.webPlaybackURL {
                        WhisperNotebookWebVideoView(url: url, model: model)
                            .frame(height: archive.snapshot.mimeType.hasPrefix("video") ? 220 : 80).clipShape(.rect(cornerRadius: 16))
                    } else if let player = model.player {
                        VideoPlayer(player: player).frame(height: !audioOnly && archive.snapshot.mimeType.hasPrefix("video") ? 220 : 80).clipShape(.rect(cornerRadius: 16))
                    }
                    HStack {
                        Label("\(WhisperRecordingArchive.time(archive.snapshot.duration)) · \(audioOnly ? "Audio backup" : archive.snapshot.mimeType.hasPrefix("video") ? "Video recording" : "Audio recording")", systemImage: "lock")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        recordingMenu
                    }
                    if let message = model.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    if archive.snapshot.transcriptionState == "incomplete" || archive.snapshot.transcriptionState == "pending" {
                        Text("This backup has unfinished transcription. Open the recording in its original browser to retry and save an updated backup.").font(.caption).foregroundStyle(.secondary)
                    }
                    RecordingTranscriptTimelineView(passages: archive.snapshot.transcript, position: model.position, onSeek: { model.seek($0, duration: archive.snapshot.duration) }, onAsk: archive.snapshot.meetingId != nil && archive.snapshot.cloudConsent == true ? { passages in jasperPassages = passages; showsJasper = true } : nil)
                    if detailsOpen {
                    Text(archive.snapshot.coverage).font(.caption).foregroundStyle(.secondary)
                    ForEach(archive.snapshot.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    DisclosureGroup("Transcript & bookmarks", isExpanded: $detailsOpen) {
                    ForEach(archive.snapshot.markers.filter(\.reviewed)) { marker in
                        Button { model.seek(marker.seconds, duration: archive.snapshot.duration) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(WhisperRecordingArchive.time(marker.seconds)) · \(marker.kind == "decision" ? "Reviewed decision" : "Bookmark")").font(.caption.weight(.semibold)).foregroundStyle(WhisperBrandGradient.rose)
                                Text(marker.title).font(.subheadline)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12).background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                    Text("Transcript · tap to listen").font(.headline)
                    Text("Times start at recording start. Approximate ranges are not exact sentence timing. Speaker identities are not inferred.").font(.caption).foregroundStyle(.secondary)
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(archive.snapshot.transcript) { passage in
                            Button { model.seek(passage.start, duration: archive.snapshot.duration) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(WhisperRecordingArchive.time(passage.start))–\(WhisperRecordingArchive.time(passage.end))\(passage.timing == "chunk" ? " · Approx." : "")").font(.caption.weight(.semibold)).foregroundStyle(WhisperBrandGradient.rose)
                                    Text(passage.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
                                    .background(model.position >= passage.start && model.position < passage.end ? WhisperTheme.card(colorScheme) : Color.clear, in: .rect(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }
                    }
                    }
                } else {
                    recordingMenu
                    ContentUnavailableView("Backup not ready", systemImage: "arrow.up.doc", description: Text(archive.state == "deleting" ? "Deletion needs to finish. Retry Delete cloud backup below." : "Resume this upload on the browser where you recorded, or delete the incomplete cloud copy. Local recordings stay untouched."))
                }
                if let error = model.errorText {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    HStack {
                        Button("Retry playback") { open() }.frame(minHeight: 44)
                        if !audioOnly { Button("Listen instead") { audioOnly = true; open() }.frame(minHeight: 44) }
                    }.font(.caption).disabled(model.isDeleting || deletionTask != nil)
                }
                if model.isDeleting { ProgressView("Removing cloud backup…") }
            }.padding(.horizontal, onClose == nil ? 16 : 0).padding(.vertical, 12)
            } else {
                ContentUnavailableView("Private recording locked", systemImage: "lock", description: Text("Sign in to the recording owner's account to reopen playback."))
            }
        }
        .scrollIndicators(.hidden).background(WhisperTheme.surface(colorScheme)).foregroundStyle(WhisperTheme.ink(colorScheme))
        .task(id: "\(archive.id):\(archive.state)") { await model.open(archive, audioOnly: audioOnly) }
        .sheet(isPresented: $showsJasper) { JasperRecordingSidekickView(archive: archive, passages: jasperPassages, onSeek: { model.seek($0, duration: archive.snapshot.duration) }).id(archive.id) }
        .onDisappear { openTask?.cancel(); deletionTask?.cancel(); model.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.pause() } }
        .onChange(of: AuthenticationService.shared.isSignedIn) { _, signedIn in
            if !signedIn { openTask?.cancel(); deletionTask?.cancel(); confirmDelete = false; model.stop() }
        }
        .onChange(of: AuthenticationService.shared.currentUser.userID) { _, _ in openTask?.cancel(); deletionTask?.cancel(); model.stop(); close() }
        .confirmationDialog("Delete this cloud snapshot?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete cloud backup", role: .destructive) {
                guard deletionTask == nil, !model.isDeleting else { return }
                openTask?.cancel()
                deletionTask = Task {
                    defer { deletionTask = nil }
                    if await model.delete(archive), !Task.isCancelled { close() }
                }
            }
            Button("Keep backup", role: .cancel) {}
        } message: { Text("Cloud media, transcript and markers will be removed. Device recordings, notes and downloaded files are kept.") }
    }
    private var recordingMenu: some View {
        Menu {
            if archive.state == "ready" {
                Button("Transcript & bookmarks", systemImage: "text.alignleft") { detailsOpen.toggle() }
                if onImportTranscript != nil, !archive.snapshot.transcript.isEmpty {
                    Button("Use transcript in this note", systemImage: "text.badge.plus") { importTranscript() }
                } else if onImportTranscript == nil, !isEmbedded {
                    Button("Link to Notebook", systemImage: "square.and.pencil") { model.linkToNotebook(archive) }
                }
                Button(audioOnly ? "Watch original recording" : "Listen to audio backup", systemImage: audioOnly ? "video" : "waveform") { audioOnly.toggle(); open() }
                Button("Reload playback", systemImage: "arrow.clockwise") { open() }
            }
            Button("Delete cloud backup", systemImage: "trash", role: .destructive) { confirmDelete = true }
            if !isEmbedded { Button("Hide player", systemImage: "chevron.up") { close() } }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
        .accessibilityLabel("Recording options").disabled(model.isDeleting || deletionTask != nil)
    }
    private func importTranscript() {
        let text = archive.snapshot.transcript.map { "[\(WhisperRecordingArchive.time($0.start))–\(WhisperRecordingArchive.time($0.end))\($0.timing == "chunk" ? "; approximate range" : "")] \($0.text)" }.joined(separator: "\n")
        guard model.isCurrent, text.utf16.count <= 60000 else { model.errorText = "This transcript exceeds one note's limit. The complete recording is kept."; return }
        onImportTranscript?(text)
    }
    private func close() { if let onClose { onClose() } else { dismiss() } }
    private func open() {
        guard !model.isDeleting, deletionTask == nil else { return }
        openTask?.cancel()
        openTask = Task { await model.open(archive, audioOnly: audioOnly) }
    }
}
