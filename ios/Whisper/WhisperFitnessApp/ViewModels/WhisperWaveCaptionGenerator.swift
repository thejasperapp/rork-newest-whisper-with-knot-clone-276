import Foundation
import Observation
import Speech
import UIKit

/// Runs on-device caption recognition across the wave's clips, one at a
/// time, and reports which clip is being listened to. Cancelling stops the
/// recognizer mid-clip and keeps whatever captions were already there.
@MainActor @Observable
final class WhisperWaveCaptionGenerator {
    var isRunning: Bool = false
    var stage: String = ""
    /// 0…1 across all clips.
    var progress: Double = 0
    var error: String?
    var isDenied: Bool = false
    private var task: Task<WhisperWaveCaptions?, Never>?

    var languageName: String { WhisperWaveCaptionService.localeName }
    var languageTag: String { WhisperWaveCaptionService.locale.identifier }

    /// Transcribes every clip. Returns nil when cancelled or when nothing could be recognized.
    func generate(_ clips: [WhisperWaveClip], keeping previous: WhisperWaveCaptions?) async -> WhisperWaveCaptions? {
        cancel()
        error = nil
        isDenied = false
        isRunning = true
        progress = 0
        stage = "Checking speech access"
        defer { isRunning = false }

        var status = WhisperWaveCaptionService.authorization
        if status == .notDetermined { status = await WhisperWaveCaptionService.requestAuthorization() }
        guard status == .authorized else {
            isDenied = status == .denied
            error = status == .restricted ? WhisperWaveCaptionService.Failure.restricted.errorDescription : WhisperWaveCaptionService.Failure.denied.errorDescription
            return nil
        }

        let language = languageTag
        let work = Task { [weak self] () -> WhisperWaveCaptions? in
            var words: [WhisperWaveCaptionWord] = []
            var seen: Set<String> = []
            let unique = clips.filter { seen.insert("\($0.url.path)|\(Int($0.trimStart * 10))|\(Int($0.trimEnd * 10))").inserted }
            for (index, clip) in unique.enumerated() {
                guard !Task.isCancelled else { return nil }
                await MainActor.run {
                    self?.stage = unique.count == 1 ? "Listening to your clip" : "Listening to clip \(index + 1) of \(unique.count)"
                    self?.progress = Double(index) / Double(unique.count)
                }
                do {
                    let found = try await WhisperWaveCaptionService.transcribe(clip)
                    words.append(contentsOf: found)
                } catch is CancellationError {
                    return nil
                } catch let failure as WhisperWaveCaptionService.Failure {
                    if case .noAudio = failure { continue }
                    await MainActor.run {
                        self?.error = failure.errorDescription
                        if case .denied = failure { self?.isDenied = true }
                    }
                    return nil
                } catch {
                    await MainActor.run { self?.error = "Captions couldn't be recognized. Retry, or check that the clip has clear speech." }
                    return nil
                }
            }
            guard !Task.isCancelled else { return nil }
            // Two clips can share one file (a split or duplicate) — keep one copy of each word.
            var deduped: [WhisperWaveCaptionWord] = []
            var keys: Set<String> = []
            for word in words.sorted(by: { $0.url.path == $1.url.path ? $0.start < $1.start : $0.url.path < $1.url.path }) {
                let key = "\(word.url.path)|\(Int((word.start * 100).rounded()))|\(word.text.lowercased())"
                if keys.insert(key).inserted { deduped.append(word) }
            }
            let style = previous?.style ?? .pop
            let highlight = previous?.highlightHex ?? "FFC94D"
            let y = previous?.y ?? 0.74
            let scale = previous?.scale ?? 1
            return WhisperWaveCaptions(words: deduped, style: style, highlightHex: highlight, y: y, scale: scale, language: language)
        }
        task = work
        let result = await work.value
        if task == work { task = nil }
        progress = 1
        if let result, result.words.isEmpty, error == nil {
            error = "No speech was found in this wave. Captions need clear spoken words."
            return nil
        }
        return result
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
