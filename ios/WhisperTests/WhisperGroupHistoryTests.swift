import Foundation
import Testing
@testable import Whisper

@MainActor
struct WhisperGroupHistoryTests {
    @Test func groupSummaryPagingRetainsRawCursorAndFullUnreadState() {
        let rows = (0..<51).map { index in
            WhisperGroupInboxSummary(group_id: UUID(), last_created_at: "2026-11-07T12:00:00.123456+00:00",
                last_message_id: "summary-\(index)", unread_count: 160,
                last_message: WhisperMessageRow(id: "summary-\(index)", from_user_id: "owner", from_username: "me",
                    to_user_id: "peer", to_username: "friend", body: "Outgoing latest", created_at: nil),
                participants: [WhisperGroupSummaryParticipant(user_id: "former-peer", username: "friend")])
        }
        let page = WhisperGroupInboxPaging.page(rows)
        #expect(page.rows.count == 50)
        #expect(page.next?.id == "summary-49")
        #expect(page.next?.createdAt == "2026-11-07T12:00:00.123456+00:00")
        #expect(page.rows.first?.unread_count == 160)
        #expect(page.rows.first?.participants.first?.user_id == "former-peer")
        #expect(WhisperGroupInboxPaging.page(Array(rows.prefix(50))).next == nil)
    }

    @Test func hundredLogicalMessagesKeepEveryDeliveryAndRawCursor() {
        let envelopes = (0..<101).map { index in
            WhisperGroupHistoryEnvelope(cursor_at: "2026-11-07T12:00:00.123456+00:00", cursor_id: "cursor-\(index)",
                messages: (0..<4).map { recipient in
                    WhisperMessageRow(id: "delivery-\(index)-\(recipient)", from_user_id: "owner", from_username: "me",
                        to_user_id: "peer-\(recipient)", to_username: "friend", body: "Message \(index)",
                        created_at: "2026-11-07T12:00:00Z", logical_group_message_id: "logical-\(index)")
                })
        }
        let recent = WhisperGroupHistory.page(envelopes, limit: 100)
        #expect(recent.rows.count == 400)
        #expect(recent.next?.id == "cursor-99")
        #expect(recent.next?.createdAt == "2026-11-07T12:00:00.123456+00:00")
        #expect(!recent.rows.contains { $0.id.hasPrefix("delivery-100-") })
        let older = WhisperGroupHistory.page(Array(envelopes.prefix(51)), limit: 50)
        #expect(older.rows.count == 200)
        #expect(older.next?.id == "cursor-49")
        #expect(WhisperGroupHistory.page(Array(envelopes.prefix(100)), limit: 100).next == nil)
    }

    @Test func closingWindowKeepsHundredLogicalMessagesAndAllCopiesPlusPending() {
        let rows = (0..<130).flatMap { index in
            (0..<3).map { recipient in
                WhisperMessageRow(id: String(format: "delivery-%03d-%d", index, recipient),
                    from_user_id: "owner", from_username: "me", to_user_id: "peer-\(recipient)", to_username: "friend",
                    body: "Message \(index)", created_at: "2026-11-07T12:00:00Z", logical_group_message_id: "logical-\(index)")
            }
        }
        let pending = WhisperMessageRow(id: "local-pending", from_user_id: "owner", from_username: "me",
            to_user_id: "peer", to_username: "friend", body: "Sending", created_at: nil)
        let retained = WhisperGroupHistory.recent(rows + [pending])
        #expect(retained.count == 301)
        #expect(retained.contains(pending))
        #expect(!retained.contains { $0.id.hasPrefix("delivery-029-") })
        #expect(retained.filter { $0.id.hasPrefix("delivery-030-") }.count == 3)
    }

    @Test func groupAndSenderIdentityNeverCollideWithDirectOrOtherGroups() {
        let group = UUID()
        let wire = "::wg-v1::\(group.uuidString)::Friends::Hello"
        let a = WhisperMessageRow(id: "a", from_user_id: "OWNER", from_username: "me", to_user_id: "peer",
            to_username: "friend", body: wire, created_at: "2026-11-07T12:00:01Z", logical_group_message_id: "LOGICAL")
        let b = WhisperMessageRow(id: "b", from_user_id: "owner", from_username: "me", to_user_id: "former-peer",
            to_username: "friend", body: wire, created_at: "2026-11-07T12:00:09Z", logical_group_message_id: "logical")
        let otherSender = WhisperMessageRow(id: "c", from_user_id: "someone-else", from_username: "friend", to_user_id: "owner",
            to_username: "me", body: wire, created_at: "2026-11-07T12:00:01Z", logical_group_message_id: "logical")
        #expect(WhisperGroupHistory.identity(a) == WhisperGroupHistory.identity(b))
        #expect(WhisperGroupHistory.identity(a) != WhisperGroupHistory.identity(otherSender))
        #expect(WhisperGroupHistory.belongs(a, to: group))
        #expect(!WhisperGroupHistory.belongs(a, to: UUID()))
    }

    @Test func staleGroupPageCannotResurrectDeletedCopyOrEraseNewReceipt() {
        let before = WhisperMessageRow(id: "delivery-a", from_user_id: "owner", from_username: "me", to_user_id: "peer",
            to_username: "friend", body: "Group message", created_at: nil, logical_group_message_id: "logical")
        let read = WhisperMessageRow(id: before.id, from_user_id: before.from_user_id, from_username: before.from_username,
            to_user_id: before.to_user_id, to_username: before.to_username, body: before.body, created_at: nil,
            read_at: "2026-11-07T13:00:00Z", logical_group_message_id: "logical")
        let unseenDeleted = WhisperMessageRow(id: "deleted-copy", from_user_id: "owner", from_username: "me", to_user_id: "other-peer",
            to_username: "friend", body: "Group message", created_at: nil, logical_group_message_id: "logical")
        let merged = WhisperMessageHistory.reconcile(fetched: [before, unseenDeleted], baseline: [before], current: [read],
            keepingHistory: true, deletedIDs: [unseenDeleted.id])
        #expect(merged == [read])
    }
}
