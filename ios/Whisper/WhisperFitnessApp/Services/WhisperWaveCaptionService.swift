import AVFoundation
import Foundation
import Speech

/// Transcribes a clip's speech on this device with word timings. The kept
/// range of the clip (plus a little padding) is written to a temporary audio
/// file first, so long source videos never send minutes of unrelated audio
/// through recognition. Nothing is uploaded: `requiresOnDeviceRecognition`
/// is mandatory, and languages without on-device support are refused.
nonisolated enum WhisperWaveCaptionService {
    nonisolated enum Failure: LocalizedError, Sendable {
        case denied
        case restricted
        case unsupportedLanguage(String)
        case noAudio
        case recognition(Int)

        var errorDescription: String? {
            switch self {
            case .denied: return "Speech recognition is off for Whisper. Turn it on in Settings to caption your waves on this iPhone."
            case .restricted: return "Speech recognition isn't allowed on this iPhone."
            case .unsupportedLanguage(let name): return "On-device captions aren't available for \(name) on this iPhone yet. Nothing is sent to a server."
            case .noAudio: return "This clip has no audio to caption."
            case .recognition(let code): return "Captions couldn't be recognized (\(code)). Retry, or check that the clip has clear speech."
            }
        }
    }

    /// The language captions will be recognized in.
    static var locale: Locale {
        let current = Locale.current
        if SFSpeechRecognizer.supportedLocales().contains(where: { $0.identifier == current.identifier }) { return current }
        if let language = current.language.languageCode?.identifier,
           let match = SFSpeechRecognizer.supportedLocales().first(where: { $0.language.languageCode?.identifier == language }) { return match }
        return Locale(identifier: "en-US")
    }

    static var localeName: String {
        let locale = locale
        return locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    static var authorization: SFSpeechRecognizerAuthorizationStatus { SFSpeechRecognizer.authorizationStatus() }

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
    }

    /// Words spoken in `clip`'s kept range, timed in the source file's seconds.
    static func transcribe(_ clip: WhisperWaveClip) async throws -> [WhisperWaveCaptionWord] {
        switch authorization {
        case .authorized: break
        case .denied, .notDetermined: throw Failure.denied
        case .restricted: throw Failure.restricted
        @unknown default: throw Failure.denied
        }
        let locale = locale
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw Failure.unsupportedLanguage(localeName)
        }
        guard recognizer.supportsOnDeviceRecognition else { throw Failure.unsupportedLanguage(localeName) }

        let pad = 0.8
        let from = max(0, clip.trimStart - pad)
        let to = min(clip.duration, clip.trimEnd + pad)
        guard to - from > 0.3 else { throw Failure.noAudio }
        let audio = try await extractAudio(clip.url, from: from, to: to)
        defer { try? FileManager.default.removeItem(at: audio) }
        try Task.checkCancellation()

        let request = SFSpeechURLRecognitionRequest(url: audio)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.addsPunctuation = true

        let segments = try await recognize(request, with: recognizer)
        var words: [WhisperWaveCaptionWord] = []
        for (index, segment) in segments.enumerated() {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = from + segment.start
            var end = from + segment.start + segment.duration
            if segment.duration < 0.05 {
                let next = index + 1 < segments.count ? from + segments[index + 1].start : start + 0.4
                end = min(next, start + 0.6)
            }
            end = max(end, start + 0.12)
            words.append(WhisperWaveCaptionWord(text: text, url: clip.url, start: start, end: end))
        }
        return words
    }

    private nonisolated struct Segment: Sendable {
        let text: String
        let start: Double
        let duration: Double
    }

    private static func recognize(_ request: SFSpeechURLRecognitionRequest, with recognizer: SFSpeechRecognizer) async throws -> [Segment] {
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Segment], any Error>) in
                let guardBox = ResumeGuard()
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        let segments = result.bestTranscription.segments.map { Segment(text: $0.substring, start: $0.timestamp, duration: $0.duration) }
                        guardBox.resume { continuation.resume(returning: segments) }
                        return
                    }
                    if let error {
                        let ns = error as NSError
                        // Silence produces "no speech detected" — an empty caption track, not a failure.
                        if ns.domain == "kAFAssistantErrorDomain" && (ns.code == 1110 || ns.code == 1107) {
                            guardBox.resume { continuation.resume(returning: []) }
                        } else {
                            print("[WaveCaptions] recognition failed domain=\(ns.domain) code=\(ns.code)")
                            guardBox.resume { continuation.resume(throwing: Failure.recognition(ns.code)) }
                        }
                    }
                }
                box.store(task)
            }
        } onCancel: {
            box.cancel()
        }
    }

    /// Writes the audio of `[from, to]` seconds to a temporary M4A.
    private static func extractAudio(_ url: URL, from: Double, to: Double) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { throw Failure.noAudio }
        let composition = AVMutableComposition()
        guard let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw Failure.noAudio }
        let range = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600), end: CMTime(seconds: to, preferredTimescale: 600))
        let available = try await track.load(.timeRange)
        let audible = CMTimeRangeGetIntersection(range, otherRange: available)
        guard audible.duration.seconds > 0.3 else { throw Failure.noAudio }
        try destination.insertTimeRange(audible, of: track, at: CMTimeSubtract(audible.start, range.start))
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else { throw Failure.noAudio }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("wave-captions-\(UUID().uuidString).m4a")
        do {
            try await session.export(to: output, as: .m4a)
        } catch {
            throw Failure.noAudio
        }
        return output
    }

    /// Holds the recognition task so cancellation can reach it from any thread.
    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: SFSpeechRecognitionTask?
        private var cancelled = false

        func store(_ task: SFSpeechRecognitionTask) {
            lock.lock()
            self.task = task
            let cancelled = self.cancelled
            lock.unlock()
            if cancelled { task.cancel() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let task = self.task
            lock.unlock()
            task?.cancel()
        }
    }

    /// A continuation may only resume once; recognition can report an error after a final result.
    private final class ResumeGuard: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false

        func resume(_ body: () -> Void) {
            lock.lock()
            let first = !resumed
            resumed = true
            lock.unlock()
            if first { body() }
        }
    }
}
