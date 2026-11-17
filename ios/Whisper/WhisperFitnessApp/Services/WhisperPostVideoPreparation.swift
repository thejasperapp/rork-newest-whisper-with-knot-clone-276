import AVFoundation
import CoreMedia
import Foundation

/// Prepares ordinary posts without the portrait crop used by Waves. Never trims source footage.
enum WhisperPostVideoPreparation {
    static func prepare(_ source: URL) async throws -> URL {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CocoaError(.fileReadCorruptFile) }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let size = try await track.load(.naturalSize)
        let rate = try await track.load(.estimatedDataRate)
        let formats = try await track.load(.formatDescriptions)
        let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if source.pathExtension.lowercased() == "mp4", bytes > 0, bytes < WhisperWaveUploadPolicy.maximumBytes,
           max(abs(size.width), abs(size.height)) <= 1920, min(abs(size.width), abs(size.height)) <= 1080,
           rate <= 6_000_000, formats.allSatisfy({ CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }) {
            return source
        }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else { throw CocoaError(.fileReadCorruptFile) }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("post-\(UUID().uuidString).mp4")
        exporter.shouldOptimizeForNetworkUse = true
        do {
            try await exporter.export(to: output, as: .mp4)
            try Task.checkCancellation()
            let count = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard count > 0, count < WhisperWaveUploadPolicy.maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
