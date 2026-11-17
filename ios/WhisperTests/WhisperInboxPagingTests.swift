import Foundation
import Testing
@testable import Whisper

@MainActor
struct WhisperInboxPagingTests {
    @Test func continuationUsesRawFiftiethRowAndPreservesMicroseconds() {
        let rows = (0..<51).map { index in
            let id = String(format: "00000000-0000-0000-0000-%012d", 100 - index)
            let message = WhisperMessageRow(id: id, from_user_id: "peer-\(index)", from_username: "friend",
                to_user_id: "owner", to_username: "me", body: "Message \(index)",
                created_at: "2026-11-07T12:00:00.123456Z")
            return WhisperInboxSummaryRow(peer_id: "peer-\(index)", conversation_kind: .direct,
                last_message_id: id, last_created_at: message.created_at,
                peer_username: "friend", unread_count: 1, last_message: message)
        }
        let page = WhisperInboxPaging.page(rows)
        #expect(page.rows.count == 50)
        #expect(page.rows.last?.last_message_id == rows[49].last_message_id)
        #expect(page.next?.id == rows[49].last_message_id)
        #expect(page.next?.createdAt == "2026-11-07T12:00:00.123456Z")
        #expect(WhisperInboxPaging.page(Array(rows.prefix(50))).next == nil)
        #expect(WhisperInboxPaging.page([]).next == nil)
    }

    @Test func completeUnreadTotalSurvivesAnOutgoingLatestMessage() {
        let message = WhisperMessageRow(id: "last", from_user_id: "OWNER", from_username: "me",
            to_user_id: "peer", to_username: "friend", body: "Newest outgoing", created_at: nil)
        let unread = WhisperInboxSummaryRow(peer_id: "PEER", conversation_kind: .direct,
            last_message_id: "last", last_created_at: nil, peer_username: nil,
            unread_count: 130, last_message: message).summary(owner: "owner")
        #expect(unread.lastFromMe)
        #expect(!unread.lastReadByMe)
        #expect(unread.otherUserID == "peer")
        #expect(unread.otherUsername == "friend")
        let read = WhisperInboxSummaryRow(peer_id: "peer", conversation_kind: .direct,
            last_message_id: "last", last_created_at: nil, peer_username: nil,
            unread_count: 0, last_message: message).summary(owner: "owner")
        #expect(read.lastReadByMe)
    }

    @Test func overlapKeepsFirstPageAndSeparatesDatingFromDirect() {
        let message = WhisperMessageRow(id: "old", from_user_id: "peer", from_username: "friend",
            to_user_id: "owner", to_username: "me", body: "Quiet chat", created_at: nil)
        let first = WhisperInboxSummaryRow(peer_id: "PEER", conversation_kind: .direct,
            last_message_id: "first", last_created_at: nil, peer_username: "friend",
            unread_count: 9, last_message: message)
        let overlap = WhisperInboxSummaryRow(peer_id: "peer", conversation_kind: .direct,
            last_message_id: "stale", last_created_at: nil, peer_username: "friend",
            unread_count: 0, last_message: message)
        let dating = WhisperInboxSummaryRow(peer_id: "peer", conversation_kind: .dating,
            last_message_id: "dating", last_created_at: nil, peer_username: "friend",
            unread_count: 1, last_message: message)
        let appended = WhisperInboxPaging.append([overlap, dating, dating], to: [first])
        #expect(appended.count == 2)
        #expect(appended[0].last_message_id == "first")
        #expect(appended[0].unread_count == 9)
        #expect(appended[1].key == "dating:peer")
        #expect(WhisperInboxPaging.append([], to: [first]).count == 1)
    }

    @Test func requestEncodesHiddenIDsAndLosslessCursor() throws {
        let params = WhisperInboxSummaryParams(p_before_at: "2026-11-07T12:00:00.123456Z",
            p_before_id: "00000000-0000-0000-0000-000000000001",
            p_hidden_ids: ["00000000-0000-0000-0000-000000000002"])
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any])
        #expect(object["p_limit"] as? Int == 50)
        #expect(object["p_before_at"] as? String == params.p_before_at)
        #expect(object["p_before_id"] as? String == params.p_before_id)
        #expect(object["p_hidden_ids"] as? [String] == params.p_hidden_ids)
    }
}
