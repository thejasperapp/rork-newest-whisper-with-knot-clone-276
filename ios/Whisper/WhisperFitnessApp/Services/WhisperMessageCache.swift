import Foundation
import CryptoKit

nonisolated enum WhisperMessageCachePolicy {
    /// Never persist access-bearing cards, media URLs, call signals or pending sends.
    static func recent(_ rows: [WhisperMessageRow], owner: String, scope: String) -> [WhisperMessageRow] {
        let me = owner.lowercased()
        let eligible = rows.filter { row in
            guard UUID(uuidString: row.id) != nil, row.notesCard == nil,
                  row.from_user_id.lowercased() == me || row.to_user_id.lowercased() == me else { return false }
            let text: String
            if scope.hasPrefix("group:"), let groupID = UUID(uuidString: String(scope.dropFirst(6))),
               let wire = WhisperGroupChatService.parse(row.body), wire.groupID == groupID {
                text = wire.body
            } else {
                guard scope == "\(row.conversationKind.rawValue):\(row.from_user_id.lowercased() == me ? row.to_user_id.lowercased() : row.from_user_id.lowercased())" else { return false }
                text = row.body
            }
            return !text.isEmpty && text.utf8.count <= 32_768 && !text.contains("::")
                && !text.lowercased().contains("https://") && !text.lowercased().contains("http://")
        }
        if scope.hasPrefix("group:") { return WhisperGroupHistory.recent(eligible).filter { !$0.id.hasPrefix("local-") } }
        let unique = Dictionary(eligible.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        return Array(unique.values.sorted { ($0.created_at ?? "", $0.id) < ($1.created_at ?? "", $1.id) }.suffix(100))
    }
}

nonisolated private struct WhisperMessageSnapshot: Codable, Sendable {
    let version: Int
    let owner: String
    let scope: String
    let savedAt: Date
    let rows: [WhisperMessageRow]
}

/// All file work is serialized off the UI actor. Separate conversation files,
/// complete iOS file protection, no backups, and a hard account-local byte LRU.
actor WhisperMessageDiskStore {
    static let shared = WhisperMessageDiskStore()
    private let root: URL
    private let maximumBytes: Int
    private var epochs: [String: UUID] = [:]

    init(root: URL? = nil, maximumBytes: Int = 25 * 1024 * 1024) {
        self.root = root ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("WhisperMessages-v1", isDirectory: true)
        self.maximumBytes = maximumBytes
    }

    func lease(owner: String) -> UUID {
        if let epoch = epochs[owner] { return epoch }
        let epoch = UUID(); epochs[owner] = epoch; return epoch
    }

    private func directory(_ owner: String) -> URL? {
        guard UUID(uuidString: owner) != nil else { return nil }
        return root.appendingPathComponent(owner.lowercased(), isDirectory: true)
    }

    private func file(_ owner: String, scope: String) -> URL? {
        directory(owner)?.appendingPathComponent(SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined() + ".json")
    }

    func load(owner: String, scope: String, lease: UUID) -> [WhisperMessageRow] {
        guard epochs[owner] == lease, let url = file(owner, scope: scope),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumBytes, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WhisperMessageSnapshot.self, from: data),
              snapshot.version == 1, snapshot.owner == owner, snapshot.scope == scope,
              Date().timeIntervalSince(snapshot.savedAt) >= 0,
              Date().timeIntervalSince(snapshot.savedAt) < 7 * 24 * 60 * 60 else { return [] }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return WhisperMessageCachePolicy.recent(snapshot.rows, owner: owner, scope: scope)
    }

    func save(_ rows: [WhisperMessageRow], owner: String, scope: String, lease: UUID) {
        guard epochs[owner] == lease, let directory = directory(owner), let url = file(owner, scope: scope) else { return }
        let retained = WhisperMessageCachePolicy.recent(rows, owner: owner, scope: scope)
        guard !retained.isEmpty else { try? FileManager.default.removeItem(at: url); return }
        let snapshot = WhisperMessageSnapshot(version: 1, owner: owner, scope: scope, savedAt: Date(), rows: retained)
        guard let data = try? JSONEncoder().encode(snapshot), data.count <= maximumBytes else {
            try? FileManager.default.removeItem(at: url); return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            var excluded = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            evict(directory)
        } catch { /* A locked device or full disk must not affect server history. */ }
    }

    private func evict(_ directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var bytes = entries.reduce(0) { $0 + $1.1 }
        var count = entries.count
        for entry in entries where bytes > maximumBytes || count > 200 {
            do { try FileManager.default.removeItem(at: entry.0); bytes -= entry.1; count -= 1 } catch { break }
        }
    }

    @discardableResult func clear(owner: String) -> Bool {
        epochs[owner] = UUID()
        guard let directory = directory(owner), FileManager.default.fileExists(atPath: directory.path) else { return true }
        do { try FileManager.default.removeItem(at: directory); return true } catch { return false }
    }

    /// Invalidate outstanding writes and remove snapshots containing changed IDs.
    /// Unknown IDs cannot resurrect because they were never in a snapshot.
    func invalidate(owner: String, ids: Set<String>) {
        epochs[owner] = UUID()
        guard let directory = directory(owner) else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in files {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(WhisperMessageSnapshot.self, from: data) else {
                try? FileManager.default.removeItem(at: url); continue
            }
            if snapshot.rows.contains(where: { ids.contains($0.id.lowercased()) }) { try? FileManager.default.removeItem(at: url) }
        }
    }

    func remove(owner: String, scope: String) {
        epochs[owner] = UUID()
        if let url = file(owner, scope: scope) { try? FileManager.default.removeItem(at: url) }
    }
}

@MainActor enum WhisperMessageCache {
    private static var revision = UUID()
    private static var changedIDs: Set<String> = []
    static var currentRevision: UUID { revision }
    private static func canUse(_ owner: String, generation: UUID, revision: UUID) -> Bool {
        let auth = AuthenticationService.shared
        return generation == AccountStorage.generation && revision == self.revision
            && UUID(uuidString: owner) != nil && AccountStorage.currentUserID.lowercased() == owner
            && auth.isSignedIn && !auth.isRestoringSession && auth.currentUser.userID.lowercased() == owner
            && WhisperBackendService.shared.isSignedInRemotely
    }

    static func load(scope: String) async -> [WhisperMessageRow] {
        let owner = AccountStorage.currentUserID.lowercased(), generation = AccountStorage.generation, revision = revision
        guard canUse(owner, generation: generation, revision: revision) else { return [] }
        let lease = await WhisperMessageDiskStore.shared.lease(owner: owner)
        guard canUse(owner, generation: generation, revision: revision), !Task.isCancelled else { return [] }
        let rows = await WhisperMessageDiskStore.shared.load(owner: owner, scope: scope, lease: lease)
        guard canUse(owner, generation: generation, revision: revision), !Task.isCancelled else { return [] }
        return rows.filter { !changedIDs.contains($0.id.lowercased()) }
    }

    static func save(_ rows: [WhisperMessageRow], scope: String, owner: String, generation: UUID, revision: UUID) async {
        let owner = owner.lowercased()
        guard canUse(owner, generation: generation, revision: revision), !Task.isCancelled else { return }
        let lease = await WhisperMessageDiskStore.shared.lease(owner: owner)
        guard canUse(owner, generation: generation, revision: revision), !Task.isCancelled else { return }
        await WhisperMessageDiskStore.shared.save(rows.filter { !changedIDs.contains($0.id.lowercased()) }, owner: owner, scope: scope, lease: lease)
    }

    static func clear(owner: String) {
        revision = UUID()
        Task { await WhisperMessageDiskStore.shared.clear(owner: owner.lowercased()) }
    }

    static func clearCurrent() async -> Bool {
        revision = UUID()
        let owner = AccountStorage.currentUserID.lowercased()
        return await WhisperMessageDiskStore.shared.clear(owner: owner)
    }

    static func invalidate(ids: Set<String>) {
        revision = UUID()
        changedIDs.formUnion(ids.map { $0.lowercased() })
        let owner = AccountStorage.currentUserID.lowercased()
        Task { await WhisperMessageDiskStore.shared.invalidate(owner: owner, ids: Set(ids.map { $0.lowercased() })) }
    }
}
