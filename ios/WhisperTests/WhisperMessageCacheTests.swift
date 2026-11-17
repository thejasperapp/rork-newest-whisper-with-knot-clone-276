import Foundation
import CryptoKit
import Testing
@testable import Whisper

@MainActor struct WhisperMessageCacheTests {
    private let owner = "00000000-0000-0000-0000-000000000001"
    private let peer = "00000000-0000-0000-0000-000000000002"

    private func row(_ index: Int, body: String = "Confirmed text") -> WhisperMessageRow {
        WhisperMessageRow(id: String(format: "00000000-0000-0000-0000-%012d", index + 10),
            from_user_id: owner, from_username: "owner", to_user_id: peer, to_username: "peer",
            body: body, created_at: "2026-11-07T12:00:00Z")
    }

    @Test func retainsOnlyOneHundredConfirmedPlainTextRows() {
        let scope = "direct:\(peer)"
        var rows = (0..<150).map { row($0) }
        rows.append(row(200, body: "::whisper-photo-v1::private"))
        rows.append(row(201, body: "https://private.invalid/media"))
        rows.append(WhisperMessageRow(id: "local-pending", from_user_id: owner, from_username: "owner", to_user_id: peer, to_username: "peer", body: "pending", created_at: nil))
        rows.append(rows[149])
        let recent = WhisperMessageCachePolicy.recent(rows, owner: owner, scope: scope)
        #expect(recent.count == 100)
        #expect(recent.first?.id == row(50).id)
        #expect(!recent.contains { $0.id.hasPrefix("local-") || $0.body.contains("::") || $0.body.contains("https://") })
        #expect(WhisperMessageCachePolicy.recent(rows, owner: peer, scope: scope).isEmpty)
        #expect(WhisperMessageCachePolicy.recent(rows, owner: owner, scope: "dating:\(peer)").isEmpty)
    }

    @Test func diskIsolationClearingAndLateWriteRejection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WhisperMessageDiskStore(root: root)
        let scope = "direct:\(peer)"
        let lease = await store.lease(owner: owner)
        await store.save([row(1)], owner: owner, scope: scope, lease: lease)
        let loaded = await store.load(owner: owner, scope: scope, lease: lease)
        #expect(loaded.map(\.id) == [row(1).id])
        let otherLease = await store.lease(owner: peer)
        let other = await store.load(owner: peer, scope: scope, lease: otherLease)
        #expect(other.isEmpty)
        await store.clear(owner: owner)
        await store.save([row(2)], owner: owner, scope: scope, lease: lease)
        let nextLease = await store.lease(owner: owner)
        let cleared = await store.load(owner: owner, scope: scope, lease: nextLease)
        #expect(cleared.isEmpty)
    }

    @Test func changedIDsRemoveSnapshotsAndRejectOlderWrites() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WhisperMessageDiskStore(root: root)
        let scope = "direct:\(peer)"
        let lease = await store.lease(owner: owner)
        await store.save([row(1)], owner: owner, scope: scope, lease: lease)
        await store.invalidate(owner: owner, ids: [row(1).id])
        await store.save([row(1)], owner: owner, scope: scope, lease: lease)
        let nextLease = await store.lease(owner: owner)
        let loaded = await store.load(owner: owner, scope: scope, lease: nextLease)
        #expect(loaded.isEmpty)
    }

    @Test func oversizedConversationCannotBreakCeiling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WhisperMessageDiskStore(root: root, maximumBytes: 400)
        let lease = await store.lease(owner: owner)
        await store.save([row(1, body: String(repeating: "a", count: 1_000))], owner: owner, scope: "direct:\(peer)", lease: lease)
        let loaded = await store.load(owner: owner, scope: "direct:\(peer)", lease: lease)
        #expect(loaded.isEmpty)
    }

    @Test func diskEvictsLeastRecentlyOpenedConversationWithinByteCeiling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WhisperMessageDiskStore(root: root, maximumBytes: 3_000)
        let lease = await store.lease(owner: owner)
        let peers = [peer, "00000000-0000-0000-0000-000000000003", "00000000-0000-0000-0000-000000000004"]
        func message(_ index: Int) -> WhisperMessageRow {
            WhisperMessageRow(id: row(index).id, from_user_id: owner, from_username: "owner",
                to_user_id: peers[index], to_username: "peer", body: String(repeating: "a", count: 700), created_at: "2026-11-07T12:00:00Z")
        }
        for index in 0..<2 {
            let scope = "direct:\(peers[index])"
            await store.save([message(index)], owner: owner, scope: scope, lease: lease)
            let filename = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
            let file = root.appendingPathComponent(owner).appendingPathComponent(filename)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index + 1))], ofItemAtPath: file.path)
        }
        let reopened = await store.load(owner: owner, scope: "direct:\(peers[0])", lease: lease)
        #expect(reopened.count == 1)
        await store.save([message(2)], owner: owner, scope: "direct:\(peers[2])", lease: lease)
        let evicted = await store.load(owner: owner, scope: "direct:\(peers[1])", lease: lease)
        let retained = await store.load(owner: owner, scope: "direct:\(peers[0])", lease: lease)
        let newest = await store.load(owner: owner, scope: "direct:\(peers[2])", lease: lease)
        #expect(evicted.isEmpty)
        #expect(retained.count == 1)
        #expect(newest.count == 1)
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(owner), includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        #expect(bytes <= 3_000)
    }

    @Test func textGroupSnapshotsRetainCompleteLogicalFanouts() {
        let group = "00000000-0000-0000-0000-000000000003"
        let rows = (0..<120).flatMap { index in
            (0..<3).map { copy in
                WhisperMessageRow(id: row(index * 3 + copy).id, from_user_id: owner, from_username: "owner",
                    to_user_id: peer, to_username: "peer", body: "::wg-v1::\(group)::Team: morning::Message \(index)",
                    created_at: "2026-11-07T12:00:00Z", logical_group_message_id: String(format: "10000000-0000-0000-0000-%012d", index))
            }
        }
        let retained = WhisperMessageCachePolicy.recent(rows, owner: owner, scope: "group:\(group)")
        #expect(retained.count == 300)
        let copies = Dictionary(grouping: retained, by: { $0.logical_group_message_id })
        #expect(copies.count == 100)
        #expect(copies.values.allSatisfy { $0.count == 3 })
        #expect(WhisperMessageCachePolicy.recent(rows, owner: owner, scope: "group:\(peer)").isEmpty)
    }

    @Test func memoryLRUEvictsLeastRecentlyViewedMonthAndClears() {
        var cache = WhisperRecentMemoryCache<String, Int>(capacity: 2)
        cache.insert(1, for: "November"); cache.insert(2, for: "December")
        #expect(cache.value(for: "November") == 1)
        cache.insert(3, for: "January")
        #expect(cache.value(for: "December") == nil)
        #expect(cache.value(for: "November") == 1)
        cache.removeAll()
        #expect(cache.value(for: "November") == nil)
        #expect(cache.value(for: "January") == nil)
    }
}
