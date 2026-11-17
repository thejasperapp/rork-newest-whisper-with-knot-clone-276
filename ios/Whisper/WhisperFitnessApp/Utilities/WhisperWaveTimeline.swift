import Foundation
import CoreGraphics

/// Shared output-clock and framing rules for preview and final export.
nonisolated enum WhisperWaveTimeline {
    static func overlap(_ clip: WhisperWaveClip, next: WhisperWaveClip?) -> Double {
        guard clip.transitionAfter != .cut, let next else { return 0 }
        let value = min(0.6, clip.effectiveSeconds / 2.5, next.effectiveSeconds / 2.5)
        return value > 0.12 ? value : 0
    }

    static func start(of id: UUID, in clips: [WhisperWaveClip]) -> Double {
        var cursor: Double = 0
        for (index, clip) in clips.enumerated() {
            if clip.id == id { return cursor }
            cursor += clip.effectiveSeconds - overlap(clip, next: index + 1 < clips.count ? clips[index + 1] : nil)
        }
        return cursor
    }

    static func duration(_ clips: [WhisperWaveClip]) -> Double {
        guard let last = clips.last else { return 0 }
        return start(of: last.id, in: clips) + last.effectiveSeconds
    }

    static func transform(_ clip: WhisperWaveClip, naturalSize: CGSize, preferred: CGAffineTransform, canvas: CGSize) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(preferred)
        let width = max(1, rect.width), height = max(1, rect.height)
        let fit = min(canvas.width / width, canvas.height / height)
        let fill = max(canvas.width / width, canvas.height / height)
        let scale = (clip.fillsFrame ? fill : fit) * min(4, max(1, clip.zoom))
        let overflowX = max(0, (width * scale - canvas.width) / 2)
        let overflowY = max(0, (height * scale - canvas.height) / 2)
        let x = min(overflowX, max(-overflowX, clip.offsetX * canvas.width))
        let y = min(overflowY, max(-overflowY, clip.offsetY * canvas.height))
        return preferred
            .concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (canvas.width - width * scale) / 2 + x, y: (canvas.height - height * scale) / 2 + y))
    }

    /// Play the chosen suffix first, then loop the full available audio source.
    static func audioSegments(duration: Double, start: Double, length: Double) -> [(source: Double, destination: Double, length: Double)] {
        guard duration.isFinite, duration > 0.1, length.isFinite, length > 0 else { return [] }
        var source = min(max(0, start.isFinite ? start : 0), max(0, duration - 0.1))
        var destination: Double = 0
        var result: [(source: Double, destination: Double, length: Double)] = []
        while destination < length {
            let count = min(duration - source, length - destination)
            guard count > 0.0001 else { break }
            result.append((source, destination, count))
            destination += count
            source = 0
        }
        return result
    }
}
