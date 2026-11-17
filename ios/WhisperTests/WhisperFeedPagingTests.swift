import Foundation
import Testing
@testable import Whisper

@MainActor
struct WhisperFeedPagingTests {
    @Test func firstPageUsesRawBoundaryAndKeepsSentinelForNextRequest() {
        let rows = (0..<25).map { index in
            WhisperPostRow(id: String(format: "00000000-0000-0000-0000-%012d", 100 - index),
                user_id: "00000000-0000-0000-0000-000000000001", username: "fixture",
                kind: "text", caption: "Post \(index)", symbol: nil, accent_hex: nil,
                media_count: 0, media_urls: [], is_ghost: false, is_reel: index % 2 == 0,
                likes_count: 25 - index, comments_count: 0,
                created_at: "2026-11-07T12:00:00.123456Z", community_id: nil, community_name: nil)
        }
        let page = WhisperFeedPaging.page(rows)
        #expect(page.rows.count == 24)
        #expect(page.rows == Array(rows.prefix(24)))
        #expect(page.next?.id == rows[23].id)
        #expect(page.next?.createdAt == rows[23].created_at)
        #expect(page.next?.beforeFilter?.contains("id.lt.\(rows[23].id)") == true)
        #expect(!page.rows.contains(rows[24]))
        #expect(WhisperFeedPaging.page(Array(rows.prefix(24))).next == nil)
        #expect(WhisperFeedPaging.page([]).rows.isEmpty)
        #expect(WhisperFeedPaging.page([]).next == nil)
    }

    @Test func continuationPreservesDisplayedOrderEditsAndDeletions() {
        let a = WhisperPostRow(id: "00000000-0000-0000-0000-00000000000a",
            user_id: "owner", username: "fixture", kind: "text", caption: "Realtime edit",
            symbol: nil, accent_hex: nil, media_count: 0, media_urls: [], is_ghost: false,
            is_reel: false, likes_count: 8, comments_count: 0, created_at: nil, community_id: nil, community_name: nil)
        let staleA = WhisperPostRow(id: a.id.uppercased(), user_id: a.user_id, username: a.username,
            kind: a.kind, caption: "Old text", symbol: nil, accent_hex: nil, media_count: 0,
            media_urls: [], is_ghost: false, is_reel: false, likes_count: 0, comments_count: 0,
            created_at: nil, community_id: nil, community_name: nil)
        let b = WhisperPostRow(id: "00000000-0000-0000-0000-00000000000b",
            user_id: "owner", username: "fixture", kind: "text", caption: "Next",
            symbol: nil, accent_hex: nil, media_count: 0, media_urls: [], is_ghost: false,
            is_reel: false, likes_count: 0, comments_count: 0, created_at: nil, community_id: nil, community_name: nil)
        #expect(WhisperFeedPaging.append([staleA, b, b], to: [a], deleted: []) == [a, b])
        #expect(WhisperFeedPaging.append([b, staleA], to: [a], deleted: [b.id]) == [a])
        #expect(WhisperFeedPaging.append([staleA, b], to: [a], deleted: [a.id]) == [b])
    }
}
