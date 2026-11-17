import Foundation

/// Legacy single-video drafts remain readable; new drafts use the account-owned edit store.
@MainActor final class WhisperReelDraftStore {
    static let shared = WhisperReelDraftStore()
    private let defaults = UserDefaults.standard
    private let captionKey = "whisper.reelDraft.caption"
    private let extKey = "whisper.reelDraft.ext"
    private init() {}
    private var fileURL: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        return dir.appendingPathComponent("whisper-reel-draft.bin")
    }
    var hasDraft: Bool { fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    func save(videoData: Data, ext: String, caption: String) {
        guard let url = fileURL else { return }
        try? videoData.write(to: url)
        defaults.set(caption, forKey: captionKey)
        defaults.set(ext, forKey: extKey)
    }
    func load() -> (videoData: Data, ext: String, caption: String)? {
        guard let url = fileURL, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return (data, defaults.string(forKey: extKey) ?? "mp4", defaults.string(forKey: captionKey) ?? "")
    }
    func clear() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        defaults.removeObject(forKey: captionKey)
        defaults.removeObject(forKey: extKey)
    }
}
