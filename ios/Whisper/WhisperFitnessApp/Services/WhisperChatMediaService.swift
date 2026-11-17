import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Supabase
import PhotosUI
import AVFoundation
import UIKit

/// Imports one attachment at a time; movies are normalized to browser-compatible H.264 MP4.
@MainActor
enum WhisperChatMediaService {
    static func upload(_ item: PhotosPickerItem, accountID: String) async throws -> String {
        let generation = AccountStorage.generation
        try checkAccount(accountID, generation: generation)
        let backend = WhisperBackendService.shared
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try await item.loadTransferable(type: WhisperPickedMovie.self) else {
                throw Failure.unreadable
            }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            let asset = AVURLAsset(url: movie.url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0, duration <= 180 else { throw Failure.tooLong }
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
                throw Failure.unreadable
            }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: output) }
            exporter.shouldOptimizeForNetworkUse = true
            try await exporter.export(to: output, as: .mp4)
            try checkAccount(accountID, generation: generation)
            let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0, bytes <= 50 * 1024 * 1024 else { throw Failure.tooLarge }
            let url = try await backend.uploadVideo(file: output, postID: UUID().uuidString, uploader: WhisperWaveUploadService())
            try checkAccount(accountID, generation: generation)
            return url
        }
        guard let data = try await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else {
            throw Failure.unreadable
        }
        guard data.count <= 50 * 1024 * 1024 else { throw Failure.tooLarge }
        try checkAccount(accountID, generation: generation)
        guard let url = await backend.uploadMedia(datas: [data], postID: UUID().uuidString).first else { throw Failure.upload }
        try checkAccount(accountID, generation: generation)
        return url
    }

    static func checkAccount(_ id: String, generation: UUID? = nil) throws {
        try Task.checkCancellation()
        if let generation, generation != AccountStorage.generation { throw Failure.accountChanged }
        guard AuthenticationService.shared.isSignedIn,
              AccountStorage.currentUserID.lowercased() == id.lowercased(),
              SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == id.lowercased() else {
            throw Failure.accountChanged
        }
    }

    nonisolated enum Failure: LocalizedError {
        case unreadable, tooLong, tooLarge, upload, accountChanged
        var errorDescription: String? {
            switch self {
            case .unreadable: "Couldn't read this attachment. Try another photo or video."
            case .tooLong: "Choose a video up to 3 minutes long."
            case .tooLarge: "Choose an attachment under 50 MB."
            case .upload: "Couldn't upload this attachment. Please try again."
            case .accountChanged: "Your account changed. Reopen the conversation before sending."
            }
        }
    }
}
