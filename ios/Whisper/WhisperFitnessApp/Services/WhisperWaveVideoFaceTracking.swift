import AVFoundation
import CoreImage
import Vision

/// Compositor-queue owned, bounded to the current transition's source clips.
/// Causal stabilization is used only for adjacent frames. Seeking, cancellation,
/// reframing and clip changes start from fresh observations, never a stale pose.
nonisolated final class WhisperWaveVideoFaceTracking {
    private struct Entry {
        let tracker: WhisperFacePoseTracker
        let extent: CGRect
        var time: CMTime
        var observations: [VNFaceObservation]
        var frames: [WhisperARProcessor.FaceFrame]
    }
    private var entries: [UUID: Entry] = [:]
    private let request = VNDetectFaceLandmarksRequest()

    func reset() { entries.removeAll() }

    func retain(_ ids: Set<UUID>) { entries = entries.filter { ids.contains($0.key) } }

    func analyze(_ image: CIImage, id: UUID, time: CMTime) throws -> (observations: [VNFaceObservation], frames: [WhisperARProcessor.FaceFrame]) {
        let previous = entries[id]
        if let previous, previous.extent == image.extent, CMTimeCompare(previous.time, time) == 0 {
            return (previous.observations, previous.frames)
        }
        do {
            let observations = try WhisperWaveFaceRenderer.detect(image, request: request)
            let tracker = previous?.tracker ?? WhisperFacePoseTracker()
            let delta = time.seconds - (previous?.time.seconds ?? time.seconds)
            // The shared composition and encoder produce 30 fps. A skipped or
            // backwards request is a seek, not evidence of continuous motion.
            if previous?.extent != image.extent || abs(delta - 1.0 / 30.0) > 0.002 { tracker.reset() }
            let frames = tracker.update(WhisperARProcessor.shared.faceFrames(observations, extent: image.extent), time: time.seconds)
            entries[id] = Entry(tracker: tracker, extent: image.extent, time: time, observations: observations, frames: frames)
            return (observations, frames)
        } catch {
            entries.removeValue(forKey: id)
            throw error
        }
    }
}
