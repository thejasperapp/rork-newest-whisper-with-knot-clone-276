import Foundation

/// Serialized, account-separated file snapshots. The manifest is committed only after every source copy succeeds.
actor WhisperWaveEditDraftStore {
    static let shared = WhisperWaveEditDraftStore()

    @discardableResult
    func save(_ draft: WhisperWaveEditDraft) throws -> WhisperWaveEditDraft {
        let root = try directory(draft.owner)
        let revision = UUID().uuidString
        let target = root.appendingPathComponent(revision, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: target) } }
        var saved = draft
        var copied: [URL: URL] = [:]
        for index in saved.clips.indices {
            let original = saved.clips[index].url
            if let existing = copied[original] { saved.clips[index].url = existing; continue }
            let ext = original.pathExtension.isEmpty ? "mp4" : original.pathExtension
            let destination = target.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: original, to: destination)
            saved.clips[index].url = destination
            copied[original] = destination
        }
        for index in saved.clips.indices {
            guard let background = saved.clips[index].background else { continue }
            if let existing = copied[background.url] { saved.clips[index].background?.url = existing; continue }
            let destination = target.appendingPathComponent("\(UUID().uuidString).\(background.url.pathExtension)")
            try FileManager.default.copyItem(at: background.url, to: destination)
            saved.clips[index].background?.url = destination
            copied[background.url] = destination
        }
        // Caption words are keyed by source file; they follow their copies.
        if var captions = saved.captions {
            let byPath = Dictionary(uniqueKeysWithValues: copied.map { ($0.key.path, $0.value) })
            captions.words = captions.words.compactMap { word in
                guard let destination = byPath[word.url.path] else { return nil }
                var moved = word
                moved.url = destination
                return moved
            }
            saved.captions = captions
        }
        try JSONEncoder().encode(saved).write(to: target.appendingPathComponent("edit.json"), options: .atomic)
        let pointer = root.appendingPathComponent("current")
        let old = try? String(contentsOf: pointer, encoding: .utf8)
        try Data(revision.utf8).write(to: pointer, options: .atomic)
        committed = true
        if let old, UUID(uuidString: old) != nil { try? FileManager.default.removeItem(at: root.appendingPathComponent(old)) }
        return saved
    }

    func setPublicationPending(owner: String, publicationID: String, pending: Bool) throws {
        guard var draft = try load(owner: owner), draft.publicationID == publicationID else { throw CocoaError(.fileNoSuchFile) }
        let root = try directory(owner)
        let revision = try String(contentsOf: root.appendingPathComponent("current"), encoding: .utf8)
        guard UUID(uuidString: revision) != nil else { throw CocoaError(.fileReadCorruptFile) }
        draft.publicationPending = pending
        try JSONEncoder().encode(draft).write(to: root.appendingPathComponent(revision).appendingPathComponent("edit.json"), options: .atomic)
    }

    func load(owner: String) throws -> WhisperWaveEditDraft? {
        let root = try directory(owner)
        let pointer = root.appendingPathComponent("current")
        guard FileManager.default.fileExists(atPath: pointer.path) else { return nil }
        let revision = try String(contentsOf: pointer, encoding: .utf8)
        guard UUID(uuidString: revision) != nil else { throw CocoaError(.fileReadCorruptFile) }
        let folder = root.appendingPathComponent(revision, isDirectory: true)
        var draft = try JSONDecoder().decode(WhisperWaveEditDraft.self, from: Data(contentsOf: folder.appendingPathComponent("edit.json")))
        guard draft.owner.lowercased() == owner.lowercased() else { throw CocoaError(.fileReadNoPermission) }
        for index in draft.clips.indices {
            draft.clips[index].url = folder.appendingPathComponent(draft.clips[index].url.lastPathComponent)
            guard FileManager.default.fileExists(atPath: draft.clips[index].url.path) else { throw CocoaError(.fileNoSuchFile) }
            if let background = draft.clips[index].background {
                // Keep missing-background metadata so the user can replace/remove it, never reveal the original room silently.
                draft.clips[index].background?.url = folder.appendingPathComponent(background.url.lastPathComponent)
            }
        }
        if var captions = draft.captions {
            let present = Set(draft.clips.map { $0.url.lastPathComponent })
            captions.words = captions.words.compactMap { word in
                guard present.contains(word.url.lastPathComponent) else { return nil }
                var moved = word
                moved.url = folder.appendingPathComponent(word.url.lastPathComponent)
                return moved
            }
            draft.captions = captions
        }
        return draft
    }

    func clear(owner: String, publicationID: String) throws {
        guard let draft = try load(owner: owner), draft.publicationID == publicationID else { return }
        let root = try directory(owner)
        let pointer = root.appendingPathComponent("current")
        guard FileManager.default.fileExists(atPath: pointer.path) else { return }
        let revision = try String(contentsOf: pointer, encoding: .utf8)
        try FileManager.default.removeItem(at: pointer)
        if UUID(uuidString: revision) != nil { try? FileManager.default.removeItem(at: root.appendingPathComponent(revision)) }
    }

    private func directory(_ owner: String) throws -> URL {
        guard UUID(uuidString: owner) != nil else { throw CocoaError(.fileWriteNoPermission) }
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("wave-edits-\(owner.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
