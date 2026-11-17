import Foundation
import Observation
import AVFoundation
import WebKit
import Supabase

@MainActor @Observable
final class WhisperRecordingArchiveViewModel {
    private(set) var archives: [WhisperRecordingArchive] = []
    private(set) var isLoading: Bool = false
    private(set) var canLoadMore: Bool = false
    private(set) var player: AVPlayer?
    private(set) var webPlaybackURL: URL?
    @ObservationIgnored weak var webPlayer: WKWebView?
    private(set) var position: Double = 0
    private(set) var isOpening: Bool = false
    private(set) var isDeleting: Bool = false
    var errorText: String?
    var message: String?
    @ObservationIgnored private let client = SupabaseService.shared.client
    @ObservationIgnored private let ownerID: String = AccountStorage.currentUserID.lowercased()
    @ObservationIgnored private let accountGeneration: UUID = AccountStorage.generation
    @ObservationIgnored private var operation: UUID = UUID()
    @ObservationIgnored private var listOperation: UUID = UUID()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    private var nextPageCursor: (id: String, created_at: String)?
    private let table: String = "whisper_recording_archives"
    private let bucket: String = "whisper-private-recordings"

    var isCurrent: Bool {
        AuthenticationService.shared.isSignedIn && ownerID == AccountStorage.currentUserID.lowercased()
        && accountGeneration == AccountStorage.generation
        && client.auth.currentUser?.id.uuidString.lowercased() == ownerID
    }
    private func check() throws {
        try Task.checkCancellation()
        guard isCurrent else { throw WhisperNotebookError.accountChanged }
    }
    func load(more: Bool = false, meetingID: String? = nil, recordingID: String? = nil, recordingIDs: [String]? = nil) async {
        guard !Task.isCancelled, !more || !isLoading else { return }
        let token = UUID(); listOperation = token
        isLoading = true; errorText = nil
        defer { if listOperation == token { isLoading = false } }
        do {
            try check()
            let previous = archives
            let oldestLoaded = more ? nil : previous.last
            let hadMore = canLoadMore
            var cursor: (id: String, created_at: String)? = more ? nextPageCursor : nil
            var incompatible = 0
            var received: [WhisperRecordingArchive] = []
            var pageIsFull = false
            repeat {
                var query = client.from(table).select().eq("owner_id", value: ownerID)
                if let meetingID { query = query.eq("snapshot->>meetingId", value: meetingID) }
                if let recordingID { query = query.eq("recording_id", value: recordingID) }
                if let recordingIDs {
                    guard !recordingIDs.isEmpty else { archives = []; canLoadMore = false; return }
                    query = query.in("recording_id", values: recordingIDs)
                }
                // Both comparisons include the unique ID so equal timestamps never skip a row.
                if let cursor {
                    query = query.or("created_at.lt.\(cursor.created_at),and(created_at.eq.\(cursor.created_at),id.lt.\(cursor.id))")
                }
                if let oldestLoaded {
                    // Revalidate the entire previously loaded range, even when new backups push it down.
                    query = query.gte("created_at", value: oldestLoaded.created_at)
                }
                let envelopes: [WhisperRecordingArchiveEnvelope] = try await query.order("created_at", ascending: false).order("id", ascending: false).limit(30).execute().value
                try check()
                guard listOperation == token else { return }
                let rows = envelopes.compactMap(\.archive).filter { $0.owner_id == ownerID && $0.isValid && (meetingID == nil || $0.snapshot.meetingId == meetingID) && (recordingID == nil || $0.recording_id == recordingID) && (recordingIDs == nil || recordingIDs?.contains($0.recording_id) == true) }
                incompatible += envelopes.count - rows.count
                guard rows.isEmpty || rows.last?.id != cursor?.id else { throw WhisperNotebookError.storage }
                received.append(contentsOf: rows)
                pageIsFull = envelopes.count == 30
                cursor = envelopes.last.map { ($0.id, $0.created_at) }
            } while oldestLoaded != nil && pageIsFull
            var seen: Set<String> = []
            archives = (more ? previous + received : received).filter { seen.insert($0.id).inserted }
            canLoadMore = oldestLoaded == nil ? pageIsFull : hadMore
            if oldestLoaded == nil { nextPageCursor = cursor }
            if incompatible > 0 { errorText = "Some recording metadata needs attention. Original media is retained; other recordings and older pages remain available." }
        } catch {
            guard listOperation == token, !Task.isCancelled else { return }
            if isCurrent { errorText = "Couldn’t open private recordings. Check your connection and try again." }
            else { archives = []; stop() }
        }
    }
    func open(_ archive: WhisperRecordingArchive, audioOnly: Bool) async {
        guard !Task.isCancelled, !isDeleting else { return }
        stop(); errorText = nil
        guard archive.isValid, archive.owner_id == ownerID, archive.state == "ready", isCurrent else { return }
        let token = operation; isOpening = true
        defer { if token == operation { isOpening = false } }
        do {
            try check()
            let rows: [WhisperRecordingArchive] = try await client.from(table).select().eq("id", value: archive.id).eq("owner_id", value: ownerID).eq("state", value: "ready").limit(1).execute().value
            try check(); guard token == operation, rows.first?.isValid == true else { throw WhisperNotebookError.storage }
            let path = "\(ownerID)/\(archive.id)/\(audioOnly ? "audio.wav" : "original")"
            let url = try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: 10800)
            try check(); guard token == operation else { return }
            // WebKit supports WebM video on iOS 17.4+; AVPlayer does not cover the same containers.
            if !audioOnly, archive.snapshot.mimeType.lowercased().contains("webm") {
                webPlaybackURL = url
                return
            }
            let item = AVPlayerItem(url: url)
            statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let failed = item.status == .failed
                Task { @MainActor [weak self] in
                    guard let self, token == self.operation else { return }
                    if !self.isCurrent { self.stop(); return }
                    if failed { self.errorText = "This file couldn’t play. Try continuous audio or reopen playback." }
                }
            }
            let created = AVPlayer(); created.replaceCurrentItem(with: item); player = created
            timeObserver = created.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.3, preferredTimescale: 600), queue: .main) { [weak self] time in
                Task { @MainActor [weak self] in
                    guard let self, token == self.operation else { return }
                    guard self.isCurrent else { self.stop(); return }
                    if time.seconds.isFinite { self.position = time.seconds }
                }
            }
        } catch {
            guard token == operation else { return }
            if isCurrent { errorText = "Couldn’t open private playback. Check your connection and try again." }
        }
    }
    func seek(_ second: Double, duration: Double) {
        guard isCurrent, second.isFinite, duration.isFinite else { stop(); return }
        let target = max(0, min(duration, second))
        if let webPlayer {
            webPlayer.evaluateJavaScript("window.seekRecording(\(target));", completionHandler: nil)
        } else if let player {
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
        }
    }
    func updateWebPlayback(position: Double?, failed: Bool, view: WKWebView) {
        guard webPlayer === view else { return }
        guard isCurrent else { stop(); return }
        if let position, position.isFinite { self.position = max(0, min(7231, position)) }
        if failed { errorText = "Video couldn’t load. Retry playback or choose the audio backup in recording options." }
    }
    func pause() {
        player?.pause()
        webPlayer?.evaluateJavaScript("document.querySelector('video')?.pause();", completionHandler: nil)
    }
    func cancelList() {
        listOperation = UUID(); isLoading = false
    }
    func stop() {
        cancelList()
        operation = UUID(); isOpening = false; pause()
        webPlayer?.stopLoading()
        webPlayer?.loadHTMLString("", baseURL: nil)
        webPlayer = nil; webPlaybackURL = nil
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil; statusObserver = nil; player?.replaceCurrentItem(with: nil); player = nil; position = 0
    }
    func linkToNotebook(_ archive: WhisperRecordingArchive) {
        guard isCurrent, archive.owner_id == ownerID, archive.isValid else { return }
        do {
            try check(); _ = try WhisperNotebookStorage.recordingNote(archive)
            message = "Recording linked in Notebook. Existing writing is unchanged; transcript import stays optional."
        } catch { errorText = "The recording is kept, but its note couldn't open. It may have been deleted or storage is full. Open Notebook to review." }
    }
    func delete(_ archive: WhisperRecordingArchive) async -> Bool {
        guard !Task.isCancelled, !isDeleting, isCurrent, archive.owner_id == ownerID, archive.isValid else { return false }
        stop(); isDeleting = true; errorText = nil
        defer { isDeleting = false }
        do {
            try check()
            let marked: [[String: String]] = try await client.from(table).update(["state": "deleting"]).eq("id", value: archive.id).eq("owner_id", value: ownerID).select("id").execute().value
            try check(); guard marked.count == 1 else { throw WhisperNotebookError.storage }
            _ = try await client.storage.from(bucket).remove(paths: ["\(ownerID)/\(archive.id)/original", "\(ownerID)/\(archive.id)/audio.wav"])
            try check()
            let removed: [[String: String]] = try await client.from(table).delete().eq("id", value: archive.id).eq("owner_id", value: ownerID).eq("state", value: "deleting").select("id").execute().value
            try check(); guard removed.count == 1 else { throw WhisperNotebookError.storage }
            archives.removeAll { $0.id == archive.id }; return true
        } catch {
            if isCurrent { errorText = "Cloud deletion did not finish. Try Delete again. Device recordings and Notebook copies are unchanged." }
            return false
        }
    }
}
