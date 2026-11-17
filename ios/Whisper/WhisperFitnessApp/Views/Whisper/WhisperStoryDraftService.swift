import Foundation
import SwiftUI
import UIKit

/// One device-local draft per account. Commit metadata only after every media
/// file is written, so a failed save never replaces the previous usable draft.
@MainActor @Observable
final class WhisperStoryDraftService {
    static let shared = WhisperStoryDraftService()

    nonisolated struct Draft: Codable, Sendable {
        let stickers: [WhisperStorySticker]
        let savedAt: Date
        let photoScale: Double
        let photoOffsetX: Double
        let photoOffsetY: Double
        var canvasWidth: Double? = nil
        var backgroundSelection: WhisperStoryBackgroundSelection? = nil
        var imageFilename: String? = nil
        var backgroundFilename: String? = nil
        var videoFilename: String? = nil
        var drawStrokes: [WhisperStoryDrawStroke]? = nil
        var music: WhisperStoryMusic? = nil
        var editedImageFilename: String? = nil
    }

    private static let metaKey = "whisper.story.draft.meta.v2"
    private(set) var draft: Draft?
    private var loadedOwner: String = ""
    private init() { reloadForCurrentAccount() }

    var hasDraft: Bool { loadedOwner == AccountStorage.currentUserID && draft != nil && imageURL != nil }
    var imageURL: URL? { fileURL(draft?.imageFilename) }
    var videoURL: URL? { fileURL(draft?.videoFilename) }

    func loadDraftImage() -> UIImage? { loadImage(draft?.imageFilename) }
    func loadBackgroundPhoto() -> UIImage? { loadImage(draft?.backgroundFilename) }
    func loadEditedImage() -> UIImage? { loadImage(draft?.editedImageFilename) }

    @discardableResult
    func save(image: UIImage, stickers: [WhisperStorySticker], photoScale: CGFloat, photoOffset: CGSize,
              canvasWidth: CGFloat? = nil, backgroundSelection: WhisperStoryBackgroundSelection? = nil,
              backgroundPhoto: UIImage? = nil, drawStrokes: [WhisperStoryDrawStroke] = [],
              music: WhisperStoryMusic? = nil, videoURL: URL? = nil, editedImage: UIImage? = nil) -> Bool {
        if loadedOwner != AccountStorage.currentUserID { reloadForCurrentAccount() }
        guard let dir = draftsDir(), let imageData = image.jpegData(compressionQuality: 0.9),
              backgroundSelection != .photo || backgroundPhoto != nil else { return false }
        let id = UUID().uuidString
        let imageName = "\(id).jpg"
        let backgroundName = backgroundPhoto == nil ? nil : "\(id)-background.jpg"
        let videoName = videoURL.map { "\(id)-video.\($0.pathExtension.isEmpty ? "mov" : $0.pathExtension)" }
        let editedName = editedImage == nil ? nil : "\(id)-edit.jpg"
        let next = Draft(stickers: stickers, savedAt: Date(), photoScale: photoScale,
                         photoOffsetX: photoOffset.width, photoOffsetY: photoOffset.height,
                         canvasWidth: canvasWidth.map { Double($0) }, backgroundSelection: backgroundSelection,
                         imageFilename: imageName, backgroundFilename: backgroundName, videoFilename: videoName,
                         drawStrokes: drawStrokes, music: music, editedImageFilename: editedName)
        do {
            let metadata = try JSONEncoder().encode(next)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try imageData.write(to: dir.appendingPathComponent(imageName), options: [.atomic, .completeFileProtection])
            if let backgroundPhoto, let backgroundName {
                guard let data = backgroundPhoto.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: dir.appendingPathComponent(backgroundName), options: [.atomic, .completeFileProtection])
            }
            if let editedImage, let editedName {
                guard let data = editedImage.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: dir.appendingPathComponent(editedName), options: [.atomic, .completeFileProtection])
            }
            if let videoURL, let videoName {
                let destination = dir.appendingPathComponent(videoName)
                try FileManager.default.copyItem(at: videoURL, to: destination)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
            }
            let previous = draft
            AccountStorage.set(metadata, forKey: Self.metaKey)
            draft = next
            removeFiles(previous, in: dir)
            return true
        } catch {
            removeFiles(next, in: dir)
            return false
        }
    }

    func clear() {
        if loadedOwner != AccountStorage.currentUserID { reloadForCurrentAccount() }
        let previous = draft
        AccountStorage.removeObject(forKey: Self.metaKey)
        draft = nil
        if let dir = draftsDir() { removeFiles(previous, in: dir) }
    }

    func reloadForCurrentAccount() {
        loadedOwner = AccountStorage.currentUserID
        // Legacy global drafts have no trustworthy owner. Leave their files
        // untouched rather than displaying another account's private composition.
        guard let data = AccountStorage.data(forKey: Self.metaKey),
              let decoded = try? JSONDecoder().decode(Draft.self, from: data) else { draft = nil; return }
        draft = decoded
        if Date().timeIntervalSince(decoded.savedAt) > 7 * 86_400 { clear() }
    }

    private func fileURL(_ name: String?) -> URL? {
        guard loadedOwner == AccountStorage.currentUserID, let name,
              (name as NSString).lastPathComponent == name, let dir = draftsDir() else { return nil }
        let url = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func loadImage(_ name: String?) -> UIImage? {
        guard let url = fileURL(name), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func removeFiles(_ draft: Draft?, in dir: URL) {
        for name in [draft?.imageFilename, draft?.backgroundFilename, draft?.videoFilename, draft?.editedImageFilename].compactMap({ $0 }) {
            guard (name as NSString).lastPathComponent == name else { continue }
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    static func removeSavedMedia(for ownerID: String) {
        if let directory = directory(for: ownerID) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func draftsDir() -> URL? { Self.directory(for: AccountStorage.currentUserID) }

    private static func directory(for ownerID: String) -> URL? {
        guard let owner = UUID(uuidString: ownerID),
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("WhisperStoryDrafts", isDirectory: true)
            .appendingPathComponent(owner.uuidString.lowercased(), isDirectory: true)
    }
}
