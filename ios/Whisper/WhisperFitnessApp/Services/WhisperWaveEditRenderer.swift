import AVFoundation
import Foundation

/// Encodes the shared frame pipeline with a full-duration upload budget.
nonisolated enum WhisperWaveEditRenderer {
    static func render(clips: [WhisperWaveClip], music: WhisperStoryMusic?, volume: Double, muted: Bool, texts: [WaveTextOverlay], filter: SnapFilter, effect: WhisperAREffect, adjustments: WhisperWaveColorAdjustments = .init(), fx: WhisperWaveFXSetting? = nil, captions: WhisperWaveCaptions? = nil, progress: @escaping @Sendable (String, Double?) async -> Void = { _, _ in }) async throws -> URL {
        guard WhisperWaveUploadPolicy.accepts(duration: WhisperWaveTimeline.duration(clips)) else {
            throw failure("Waves can be up to 6 minutes after trimming and speed changes. Your original clips are unchanged.")
        }
        await progress("Preparing audio", nil)
        var localMusic: URL?
        if let music {
            guard let remote = URL(string: music.previewURL), let local = await WhisperWaveStudio.localCopy(of: remote) else {
                throw failure("The selected audio couldn't be loaded. Retry or choose another sound.")
            }
            localMusic = local
        }
        defer { if let localMusic, localMusic.absoluteString != music?.previewURL { try? FileManager.default.removeItem(at: localMusic) } }
        try Task.checkCancellation()
        await progress("Preparing clips", nil)
        guard let built = await WhisperWaveClipStudio.makeComposition(clips, musicURL: localMusic, musicStart: music?.startSeconds ?? 0, musicVolume: Float(volume), muteOriginal: muted, filter: filter, adjustments: adjustments, effect: effect, fx: fx, quality: .final, texts: texts, captions: captions) else {
            throw failure("A clip, background or audio track couldn't be read. Nothing was posted. Replace missing media in Clips / Green Screen and retry.")
        }
        do {
            return try await WhisperWaveBudgetEncoder().encode(asset: built.asset, video: built.video, audio: built.audio, progress: progress)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let ns = error as NSError
            if ns.domain == "WhisperWaveEdit" { throw error }
            print("[WaveExport] failed domain=\(ns.domain) code=\(ns.code)")
            throw failure("Video rendering failed (\(ns.code)). Your edits are safe. Free some device storage and retry, or check the selected clips.")
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "WhisperWaveEdit", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
