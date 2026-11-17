import Foundation
import CoreImage
import ImageIO
import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

/// File-transfer imports avoid reading an entire video into memory. No photo-library-wide access is requested.
nonisolated enum WhisperWaveBackgroundImporter {
    struct PickedPhoto: Transferable, Sendable {
        let url: URL
        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(importedContentType: .image) { received in
                let ext = received.file.pathExtension.isEmpty ? "heic" : received.file.pathExtension
                let target = FileManager.default.temporaryDirectory.appendingPathComponent("wave-background-\(UUID().uuidString).\(ext)")
                try FileManager.default.copyItem(at: received.file, to: target)
                return PickedPhoto(url: target)
            }
        }
    }

    static func image(at url: URL) throws -> CIImage {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2560, kCGImageSourceShouldCacheImmediately: true]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        return CIImage(cgImage: image)
    }

    @MainActor static func load(_ item: PhotosPickerItem) async throws -> WhisperWaveBackground {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try await item.loadTransferable(type: WhisperPickedMovie.self) else { throw CocoaError(.fileReadCorruptFile) }
            do {
                let duration = await WhisperWaveClipStudio.duration(of: movie.url)
                try Task.checkCancellation()
                guard duration > 0.1 else { throw CocoaError(.fileReadCorruptFile) }
                return WhisperWaveBackground(url: movie.url, media: .video)
            } catch { try? FileManager.default.removeItem(at: movie.url); throw error }
        }
        guard let photo = try await item.loadTransferable(type: PickedPhoto.self) else { throw CocoaError(.fileReadCorruptFile) }
        do {
            try Task.checkCancellation()
            _ = try await Task.detached(priority: .userInitiated) { try image(at: photo.url) }.value
            try Task.checkCancellation()
            return WhisperWaveBackground(url: photo.url, media: .photo)
        } catch { try? FileManager.default.removeItem(at: photo.url); throw error }
    }
}
