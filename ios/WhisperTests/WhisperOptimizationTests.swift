import Foundation
import Testing
@testable import Whisper

struct WhisperOptimizationTests {
    @Test func datingIdentityIsSymmetricAndSeparate() {
        let a = "00000000-0000-4000-8000-000000000001"
        let b = "00000000-0000-4000-8000-000000000002"
        let direct = WhisperConversationKind.direct.threadID(a, b)
        let dating = WhisperConversationKind.dating.threadID(a, b)
        #expect(direct != dating)
        #expect(dating == WhisperConversationKind.dating.threadID(b.uppercased(), a.uppercased()))
        #expect(WhisperConversationKind.resolve(threadID: dating, first: a, second: b) == .dating)
        #expect(WhisperConversationKind.resolve(threadID: nil, first: a, second: b) == .direct)
        #expect(WhisperConversationKind.dating.localKey(peer: b) != WhisperConversationKind.direct.localKey(peer: b))
    }

    @Test func messageRoundTripPreservesDatingIdentity() throws {
        let a = "00000000-0000-4000-8000-000000000001"
        let b = "00000000-0000-4000-8000-000000000002"
        let row = WhisperMessageRow(id: UUID().uuidString, from_user_id: a, from_username: "a", to_user_id: b, to_username: "b", body: "Hello", created_at: nil, thread_id: WhisperConversationKind.dating.threadID(a, b))
        let decoded = try JSONDecoder().decode(WhisperMessageRow.self, from: JSONEncoder().encode(row))
        #expect(decoded.thread_id == row.thread_id)
        #expect(decoded.conversationKind == .dating)
    }

    @MainActor @Test func replyRetriesRetainIdentityUntilContentChanges() {
        let attachments = WhisperComposerAttachments()
        let original = attachments.commentID(baseBody: "Hello", postID: "post", parentID: nil)
        #expect(attachments.commentID(baseBody: "Hello", postID: "post", parentID: nil) == original)
        #expect(attachments.commentID(baseBody: "Edited", postID: "post", parentID: nil) != original)
    }

    @MainActor @Test func dmNormalizationKeepsThreadAndMessage() {
        let payload = normalizedWhisperPayload(["kind": "dm", "thread_id": "thread", "message_id": "message", "recipient_user_id": "owner"], title: "Sample")
        #expect(payload?["threadID"] == "thread")
        #expect(payload?["messageID"] == "message")
        #expect(payload?["recipientUID"] == "owner")
    }

    @MainActor @Test func longOrdinaryTextDoesNotBecomeJasper() {
        #expect(WhisperMessageStyleGlyph.style(for: String(repeating: "Long ordinary message. ", count: 80)).symbol == "text.bubble")
        #expect(WhisperMessageStyleGlyph.style(for: "https://example.com/movie.mp4").symbol == "video")
        #expect(WhisperMatchWire.decode("::whisper-matched-v1::{bad") == nil)
    }
}
