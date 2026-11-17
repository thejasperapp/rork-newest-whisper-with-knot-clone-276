import Foundation
import Testing
@testable import Whisper

struct WhisperSocialReliabilityTests {
    @MainActor @Test func notificationNormalizationRetainsDestinationsAndOwner() {
        let comment = normalizedWhisperPayload(["kind": "comment", "post_id": "post", "comment_id": "comment", "recipient_user_id": "owner"], title: "")
        #expect(comment?["postID"] == "post")
        #expect(comment?["commentID"] == "comment")
        #expect(comment?["recipientUID"] == "owner")
        let story = normalizedWhisperPayload(["kind": "story_response", "story_id": "story", "response_id": "response", "recipient_user_id": "owner"], title: "")
        #expect(story?["storyID"] == "story")
        #expect(story?["responseID"] == "response")
        #expect(story?["recipientUID"] == "owner")
    }

    @Test func storyLikesAndReactionsAreNotQuestionAnswers() {
        for (kind, expected) in [("like", "liked your story"), ("reaction", "reacted to your story with"), ("question", "answered your question with"), ("future", "responded to your story with")] {
            let row = WhisperStoryResponseRow(id: "response", story_id: "story", story_owner_id: "owner", responder_id: "sender", responder_username: "sample", kind: kind, prompt: "", response: "", created_at: nil, read_at: nil)
            #expect(row.actionDescription == expected)
        }
    }

    @MainActor @Test func threadCacheUpdatesBodyAndReceiptWithoutCountChange() {
        let key = "regression-" + UUID().uuidString
        let first = WhisperMessageRow(id: "1", from_user_id: "owner", from_username: "sample", to_user_id: "other", to_username: "other", body: "before", created_at: "2026-09-23T12:00:00Z")
        let edited = WhisperMessageRow(id: "1", from_user_id: "owner", from_username: "sample", to_user_id: "other", to_username: "other", body: "after", created_at: "2026-09-23T12:00:00Z", read_at: "2026-09-23T12:01:00Z")
        let old = WhisperChatThreadIndex.shared.index(key: key, rows: [first], currentUIDLower: "owner", revision: 1)
        let updated = WhisperChatThreadIndex.shared.index(key: key, rows: [edited], currentUIDLower: "owner", revision: 2)
        #expect(old.messages.first?.body == "before")
        #expect(updated.messages.first?.body == "after")
        #expect(updated.lastSeenMineID == "1")
        let otherOwner = WhisperChatThreadIndex.shared.index(key: key, rows: [edited], currentUIDLower: "other", revision: 2)
        #expect(otherOwner.lastSeenMineID == nil)
    }
}
