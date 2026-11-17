import Foundation
import CryptoKit

/// Protected, account-qualified originals. Metadata is not evicted with bytes.
/// All mutations are serialized on the UI actor; async work carries a lease so
/// sign-out, withdrawal or a deleted conversation cannot be repopulated later.
@MainActor enum WhisperKnotOriginalStore {
    private static var epoch = UUID()
    private static var deleted = Set<String>()
    private static let byteLimit = 200_000_000
    private static var flights: [String: (id: UUID, task: Task<URL, Error>)] = [:]
    private static var pins: [UUID: URL] = [:]
    struct Lease {
        let owner: String
        let generation: UUID
        let permission: UUID
        let epoch: UUID
        let conversationID: UUID
        let directMessage: Bool
        var valid: Bool {
            owner == AccountStorage.currentUserID.lowercased() && generation == AccountStorage.generation &&
            epoch == WhisperKnotOriginalStore.epoch && !deleted.contains(owner + ":" + conversationID.uuidString) &&
            (directMessage ? WhisperKnotDMArtifacts.allowed(conversationID) :
                permission == WhisperKnotContextPermission.revision && WhisperKnotContextPermission.allowed && !WhisperEmberHistoryStore.shared.isDeleted(conversationID))
        }
    }
    static func lease(_ conversationID: UUID, directMessage: Bool = false) throws -> Lease {
        guard UUID(uuidString: AccountStorage.currentUserID) != nil,
              directMessage ? WhisperKnotDMArtifacts.allowed(conversationID) : WhisperKnotContextPermission.allowed else { throw CancellationError() }
        let owner = AccountStorage.currentUserID.lowercased()
        if UserDefaults.standard.bool(forKey: "KnotOriginalsRemoval-" + hash(owner)) {
            if FileManager.default.fileExists(atPath: root(owner).path) { try FileManager.default.removeItem(at: root(owner)) }
            UserDefaults.standard.removeObject(forKey: "KnotOriginalsRemoval-" + hash(owner))
        }
        let value = Lease(owner: owner, generation: AccountStorage.generation,
                          permission: WhisperKnotContextPermission.revision, epoch: epoch, conversationID: conversationID, directMessage: directMessage)
        guard value.valid else { throw CancellationError() }; return value
    }
    private static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func root(_ owner: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KnotOriginals-v1", isDirectory: true).appendingPathComponent(hash(owner.lowercased()), isDirectory: true)
    }
    private static func thread(_ lease: Lease, bot: String) -> URL {
        root(lease.owner).appendingPathComponent(hash(bot + ":" + lease.conversationID.uuidString.lowercased()), isDirectory: true)
    }
    private static func directory(_ lease: Lease, bot: String, document: WhisperKnotDocument) -> URL {
        thread(lease, bot: bot).appendingPathComponent(document.id, isDirectory: true)
    }
    private static func prepare(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var target = url; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try target.setResourceValues(values)
    }
    private static func write(_ data: Data, to url: URL) throws {
        try prepare(url.deletingLastPathComponent())
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
    private static func isMetadata(_ url: URL, owner: String) -> Bool {
        url.lastPathComponent == "cards.json" && url.deletingLastPathComponent().deletingLastPathComponent() == root(owner)
    }
    static func pin(_ document: WhisperKnotDocument, bot: String, conversationID: UUID) throws -> UUID {
        let lease = try lease(conversationID, directMessage: bot == WhisperKnotDMArtifacts.storageBot), token = UUID()
        pins[token] = directory(lease, bot: bot, document: document)
        return token
    }
    static func releasePin(_ token: UUID?) { if let token { pins.removeValue(forKey: token) } }
    static func documents(bot: String, lease: Lease) -> [WhisperKnotDocument] {
        guard lease.valid, let data = try? Data(contentsOf: thread(lease, bot: bot).appendingPathComponent("cards.json")), data.count <= 2_000_000,
              let values = try? JSONDecoder().decode([WhisperKnotDocument].self, from: data) else { return [] }
        var seen = Set<String>()
        return Array(values.filter { $0.valid && seen.insert($0.id).inserted }.prefix(500))
    }
    static func merged(_ incoming: [WhisperKnotDocument], retaining existing: [WhisperKnotDocument]) throws -> [WhisperKnotDocument] {
        var cards: [String: WhisperKnotDocument] = [:]
        for card in existing + incoming where card.valid {
            if let previous = cards[card.id], !previous.identifiesSameOriginal(as: card) {
                throw WhisperKnotFileError.server("document_identity_changed")
            }
            cards[card.id] = card
        }
        return cards.values.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }
    static func save(_ values: [WhisperKnotDocument], bot: String, lease: Lease) throws {
        guard lease.valid else { throw CancellationError() }
        // Re-read within this serialized write. Another view may have saved a
        // delivery while this view's network request was in flight.
        let values = try merged(values, retaining: documents(bot: bot, lease: lease))
        guard values.count <= 500 else { throw WhisperKnotFileError.capacity }
        let data = try JSONEncoder().encode(values)
        guard data.count <= 2_000_000 else { throw WhisperKnotFileError.capacity }
        let target = thread(lease, bot: bot).appendingPathComponent("cards.json")
        var count = values.count; var total = data.count
        if let enumerator = FileManager.default.enumerator(at: root(lease.owner), includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in enumerator where isMetadata(url, owner: lease.owner) && url != target {
                guard let other = try? Data(contentsOf: url), other.count <= 2_000_000,
                      let cards = try? JSONDecoder().decode([WhisperKnotDocument].self, from: other) else { continue }
                count += cards.count; total += other.count
                guard count <= 500, total <= 2_000_000 else { throw WhisperKnotFileError.capacity }
            }
        }
        try write(data, to: target)
    }
    static func original(_ document: WhisperKnotDocument, bot: String, conversationID: UUID) async throws -> URL {
        let lease = try lease(conversationID, directMessage: bot == WhisperKnotDMArtifacts.storageBot)
        let key = "\(lease.owner):\(bot):\(conversationID):\(document.id):\(lease.generation):\(lease.epoch):\(lease.permission)"
        if let flight = flights[key] {
            let url = try await flight.task.value
            guard lease.valid, !Task.isCancelled else { throw CancellationError() }; return url
        }
        let id = UUID()
        let task = Task { try await loadOriginal(document, bot: bot, conversationID: conversationID, lease: lease) }
        flights[key] = (id, task)
        defer { if flights[key]?.id == id { flights.removeValue(forKey: key) } }
        let url = try await task.value
        guard lease.valid, !Task.isCancelled else { throw CancellationError() }; return url
    }
    private static func loadOriginal(_ document: WhisperKnotDocument, bot: String, conversationID: UUID, lease: Lease) async throws -> URL {
        let url = directory(lease, bot: bot, document: document).appendingPathComponent(document.name)
        if await verified(url, size: document.size, sha256: document.sha256) {
            guard lease.valid, !Task.isCancelled else { throw CancellationError() }
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return url
        }
        let data = try await WhisperKnotDocumentService.resource(document, bot: bot, conversationID: conversationID)
        guard lease.valid, !Task.isCancelled else { throw CancellationError() }
        try makeRoom(for: data.count, replacing: url, keeping: directory(lease, bot: bot, document: document), lease: lease)
        try write(data, to: url)
        return url
    }
    static func bundle(_ document: WhisperKnotDocument, bot: String, conversationID: UUID) async throws -> [String: URL] {
        let lease = try lease(conversationID, directMessage: bot == WhisperKnotDMArtifacts.storageBot)
        let entry = try await original(document, bot: bot, conversationID: conversationID)
        var result = [document.name: entry]
        for asset in document.bundle?.assets ?? [] {
            guard lease.valid, !Task.isCancelled else { throw CancellationError() }
            // Same protected artifact directory, never a path supplied by HTML.
            let url = directory(lease, bot: bot, document: document).appendingPathComponent(asset.path)
            if !(await verified(url, size: asset.size, sha256: asset.sha256)) {
                let data = try await WhisperKnotDocumentService.asset(document, asset: asset, bot: bot, conversationID: conversationID)
                guard lease.valid, !Task.isCancelled else { throw CancellationError() }
                try makeRoom(for: data.count, replacing: url, keeping: directory(lease, bot: bot, document: document), lease: lease)
                try write(data, to: url)
            }
            result[asset.path] = url
        }
        guard lease.valid else { throw CancellationError() }
        return result
    }
    @concurrent private static func verified(_ url: URL, size: Int, sha256: String) async -> Bool {
        guard !Task.isCancelled, let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count == size else { return false }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == sha256
    }
    private static func makeRoom(for size: Int, replacing: URL, keeping: URL, lease: Lease) throws {
        guard lease.valid else { throw CancellationError() }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: root(lease.owner), includingPropertiesForKeys: keys) else { return }
        var files: [(URL, Int, Date)] = []; var total = 0
        for case let url as URL in enumerator {
            guard !isMetadata(url, owner: lease.owner), let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            // Capacity describes the resulting store, not the corrupt bytes
            // being atomically replaced by the identical verified original.
            let bytes = values.fileSize ?? 0
            if url == replacing { continue }
            total += bytes
            let inUse = pins.values.contains { url.path.hasPrefix($0.path + "/") }
            if !url.path.hasPrefix(keeping.path + "/") && !inUse { files.append((url, bytes, values.contentModificationDate ?? .distantPast)) }
        }
        for (url, bytes, _) in files.sorted(by: { $0.2 < $1.2 }) where total + size > byteLimit {
            try FileManager.default.removeItem(at: url); total -= bytes
        }
        guard total + size <= byteLimit else { throw WhisperKnotFileError.capacity }
    }
    static func clear(owner: String) {
        WhisperKnotHTMLSessions.clear(owner: owner)
        WhisperKnotDMArtifacts.clear(owner: owner)
        epoch = UUID()
        pins.removeAll()
        flights.values.forEach { $0.task.cancel() }; flights.removeAll()
        let key = "KnotOriginalsRemoval-" + hash(owner.lowercased())
        UserDefaults.standard.set(true, forKey: key)
        do {
            if FileManager.default.fileExists(atPath: root(owner).path) { try FileManager.default.removeItem(at: root(owner)) }
            UserDefaults.standard.removeObject(forKey: key)
        } catch { print("knot_original_clear_unavailable") }
    }
    static func delete(conversationID: UUID) {
        let owner = AccountStorage.currentUserID.lowercased()
        WhisperKnotHTMLSessions.clear(owner: owner, conversationID: conversationID)
        epoch = UUID(); deleted.insert(owner + ":" + conversationID.uuidString)
        for bot in WhisperKnotBot.allCases {
            let value = root(owner).appendingPathComponent(hash(bot.rawValue + ":" + conversationID.uuidString.lowercased()), isDirectory: true)
            pins = pins.filter { !$0.value.path.hasPrefix(value.path + "/") }
            do { if FileManager.default.fileExists(atPath: value.path) { try FileManager.default.removeItem(at: value) } }
            catch { print("knot_original_delete_unavailable") }
        }
        NotificationCenter.default.post(name: .init("WhisperKnotFilesDeleted"), object: conversationID)
    }
}

nonisolated enum WhisperKnotFileError: LocalizedError {
    case server(String), capacity, preview
    var errorDescription: String? {
        switch self {
        case .capacity: return "File storage is full. The delivery card is kept; try again after freeing device storage."
        case .preview: return "This file could not be previewed. You can still share or save its original."
        case .server(let code):
            switch code {
            case "document_identity_changed": return "The refreshed card does not match the saved original. Your existing card and file were kept; no replacement was accepted."
            case "document_source_changed": return "The workspace file has changed. This card still identifies the delivered original; it was not replaced or regenerated."
            case "document_source_missing": return "The original workspace path is missing or was renamed. No replacement was generated."
            case "document_original_unavailable": return "The original delivery copy is no longer available, and its source identity could not be recovered. The card is kept."
            case "document_removed": return "This delivery is no longer available on the server."
            default: return "The original file couldn’t be retrieved. The card is kept. Tap Retry to try again."
            }
        }
    }
}
