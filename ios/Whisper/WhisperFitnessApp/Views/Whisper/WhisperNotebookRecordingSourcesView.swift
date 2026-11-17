import SwiftUI

/// Playback belongs to the meeting, not to the existence of a writable note.
struct WhisperNotebookRecordingSourcesView: View {
    let meetingID: String?
    var recordingID: String? = nil
    var attachmentIDs: [String]? = nil
    var refreshID: UUID? = nil
    var onRecordingChange: ((WhisperRecordingArchive?) -> Void)? = nil
    var onImportTranscript: ((String) -> Void)? = nil
    var onAttach: ((WhisperRecordingArchive) -> Void)? = nil
    var onContext: ((WhisperNotebookContext) -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: WhisperRecordingArchiveViewModel = WhisperRecordingArchiveViewModel()
    @State private var exactModel: WhisperRecordingArchiveViewModel = WhisperRecordingArchiveViewModel()
    @State private var selected: String?
    @State private var hasLoaded: Bool = false
    @State private var loadToken: UUID = UUID()

    private var exactIDs: [String] { Array(Set((recordingID.map { [$0] } ?? []) + (attachmentIDs ?? []))).sorted() }
    private var missingAttachments: [String] { (attachmentIDs ?? []).filter { id in !sources.contains { $0.recording_id == id } } }
    private var sources: [WhisperRecordingArchive] {
        guard model.isCurrent, exactModel.isCurrent else { return [] }
        var seen: Set<String> = []
        return (exactModel.archives + model.archives).filter {
            (exactIDs.contains($0.recording_id) || (meetingID != nil && $0.snapshot.meetingId == meetingID)) && seen.insert($0.id).inserted
        }
    }
    private var active: WhisperRecordingArchive? {
        if let choice = sources.first(where: { $0.id == selected }) { return choice }
        if let exact = sources.first(where: { exactIDs.contains($0.recording_id) && $0.state == "ready" }) { return exact }
        guard hasLoaded else { return nil }
        if attachmentIDs?.isEmpty == false { return sources.first { exactIDs.contains($0.recording_id) } }
        return sources.first { $0.state == "ready" } ?? sources.first
    }
    private var lookupFailed: Bool { model.errorText != nil || exactModel.errorText != nil }
    private var isLoading: Bool { !hasLoaded || model.isLoading || exactModel.isLoading }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let archive = active {
                if !exactIDs.contains(archive.recording_id) {
                    Text("Another recording from this meeting").font(.caption).foregroundStyle(.secondary)
                }
                if attachmentIDs?.contains(archive.recording_id) == true { Text("Attached recording").font(.caption).foregroundStyle(.secondary) }
                if let onAttach, !exactIDs.contains(archive.recording_id) { Button("Attach this recording to note") { onAttach(archive) }.font(.caption).frame(minHeight: 44) }
                WhisperRecordingArchivePlayerView(archive: archive, onClose: { Task { await load() } }, onImportTranscript: onImportTranscript, isEmbedded: true)
                    .id(archive.id)
                if let onContext { WhisperNotebookRecordingPassagesView(archive: archive, onChoose: onContext).id(archive.id) }
                if sources.count > 1 || model.canLoadMore || exactModel.canLoadMore {
                    Menu {
                        ForEach(sources) { item in
                            Button("\(item.title) · \(WhisperRecordingArchive.time(item.snapshot.duration))\(item.state == "ready" ? "" : " · Incomplete")") {
                                selected = item.id; Haptics.tap()
                            }
                        }
                        if model.canLoadMore {
                            Button("Load older recordings") { Task { await model.load(more: true, meetingID: meetingID) } }.disabled(model.isLoading)
                        }
                        if exactModel.canLoadMore {
                            Button("Load older copies of this recording") { Task { await exactModel.load(more: true, recordingIDs: exactIDs) } }.disabled(exactModel.isLoading)
                        }
                    } label: { Label("Recordings in this meeting", systemImage: "chevron.down").font(.caption).frame(minHeight: 44) }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label(isLoading ? "Finding your recording…" : lookupFailed ? "Recording lookup unavailable" : "No recording available here", systemImage: "video")
                        .font(.headline)
                    if isLoading { ProgressView().accessibilityLabel("Checking private recordings") }
                    else {
                        Text(lookupFailed ? "We couldn’t check your private backups. Your notes are still available below." : "iPhone plays private backups saved by this account. If you recorded on the web, open that same browser and save a permitted private backup. A shared recap does not include the host’s video.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Check again") { Task { await load() } }.frame(minHeight: 44)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .background(.secondary.opacity(0.06), in: .rect(cornerRadius: 18))
            }
            if active == nil, model.canLoadMore { Button("Load older recordings") { Task { await model.load(more: true, meetingID: meetingID) } }.disabled(model.isLoading) }
            if active == nil, exactModel.canLoadMore { Button("Load older copies of this recording") { Task { await exactModel.load(more: true, recordingIDs: exactIDs) } }.disabled(exactModel.isLoading) }
            if !missingAttachments.isEmpty, !isLoading {
                Text("\(missingAttachments.count) attached recording(s) unavailable here. Retry private backups. No other recording was substituted.").font(.caption).foregroundStyle(.secondary)
            }
            if active == nil, let other = sources.first, !isLoading { Button("Browse other recordings from this meeting") { selected = other.id }.font(.caption).frame(minHeight: 44) }
            if active != nil, lookupFailed {
                Button("Some recordings couldn’t load · Retry") { Task { await load() } }.font(.caption).frame(minHeight: 44)
            }
        }
        .task(id: "\(meetingID ?? "none"):\(recordingID ?? "none"):\(exactIDs.joined(separator: ",")):\(refreshID?.uuidString ?? "initial")") { await load() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                if active?.state != "ready" { await load() }
            }
        }
        .onChange(of: active?.id, initial: true) { _, id in
            if let id { selected = id }
            onRecordingChange?(active)
        }
        .onChange(of: active?.state) { _, _ in onRecordingChange?(active) }
        .onChange(of: AuthenticationService.shared.isSignedIn) { _, signedIn in
            if !signedIn { loadToken = UUID(); model.stop(); exactModel.stop(); onRecordingChange?(nil) }
        }
        .onDisappear { loadToken = UUID(); model.stop(); exactModel.stop() }
    }

    private func load() async {
        guard !Task.isCancelled else { return }
        if !model.isCurrent || !exactModel.isCurrent { return }
        let token = UUID(); loadToken = token
        if !exactIDs.isEmpty {
            async let exact: Void = exactModel.load(recordingIDs: exactIDs)
            if let meetingID { await model.load(meetingID: meetingID) }
            _ = await exact
        } else if let meetingID { await model.load(meetingID: meetingID) }
        guard !Task.isCancelled, loadToken == token, model.isCurrent, exactModel.isCurrent else { return }
        hasLoaded = true
    }
}
