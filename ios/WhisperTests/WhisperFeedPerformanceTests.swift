import Testing
import SwiftUI
import UIKit
@testable import Whisper

@MainActor
struct WhisperFeedPerformanceTests {
    @Test func displaySizingUsesRetinaBucketsAndBoundsMemory() {
        #expect(WhisperSizedAsyncImage<EmptyView>.pixelSize(size: CGSize(width: 120, height: 120), scale: 3) == CGSize(width: 384, height: 384))
        #expect(WhisperSizedAsyncImage<EmptyView>.pixelSize(size: CGSize(width: 390, height: 488), scale: 3) == CGSize(width: 1280, height: 1536))
        #expect(WhisperSizedAsyncImage<EmptyView>.pixelSize(size: CGSize(width: 10000, height: 10000), scale: 3) == CGSize(width: 3072, height: 3072))
        #expect(WhisperImageCache.aspectFillLimit(source: CGSize(width: 4000, height: 400), target: CGSize(width: 384, height: 384)) == 3840)
    }

    @Test func aspectFillDecoderKeepsPanoramaCropSharp() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 400), format: format).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4000, height: 400))
        }
        let data = try #require(source.pngData())
        let image = try #require(WhisperImageCache.decode(data, maxPixelSize: nil, fillPixelSize: CGSize(width: 384, height: 384))?.cgImage)
        #expect(image.width == 3840 && image.height == 384)
        let original = try #require(WhisperImageCache.decode(data, maxPixelSize: nil)?.cgImage)
        #expect(original.width == 4000 && original.height == 400)
    }

    @Test func lookAheadSkipsVideosAndPreservesSignedIdentities() throws {
        let video = try #require(URL(string: "https://example.com/movie.mp4"))
        let first = try #require(URL(string: "https://example.com/image.jpg?token=a"))
        let second = try #require(URL(string: "https://example.com/image.jpg?token=b"))
        let posts = [video, first, second, first].map { url in
            WhisperPost(username: "fixture", timeAgo: "now", kind: .photo, caption: "", symbol: "photo", accent: .gray,
                        mediaURLs: [url], likes: 0, comments: 0)
        }
        #expect(WhisperFeedImagePrefetcher.imageURLs(in: posts) == [first, second])
        #expect(WhisperFeedImagePrefetcher.imageURLs(in: [posts[1], posts[1]]) == [first])
    }

    @Test func projectionPatchesLikesAndPrunesRemovedRows() {
        let id = UUID().uuidString.lowercased()
        let owner = UUID().uuidString.lowercased()
        let row = WhisperPostRow(id: id, user_id: owner, username: "fixture", kind: "photo", caption: "Unchanged caption",
            symbol: nil, accent_hex: nil, media_count: 1, media_urls: ["https://example.com/photo.jpg"], is_ghost: false,
            is_reel: false, likes_count: 3, comments_count: 1, created_at: "2026-09-24T12:00:00Z", community_id: nil, community_name: nil)
        let projection = WhisperFeedProjection()
        projection.update(rows: [row], names: [owner: "fixture"], likedIDs: [])
        let originalIDs = projection.posts.map(\.id)
        let originalDate = projection.posts.first?.createdAt
        projection.update(rows: [row], names: [owner: "fixture"], likedIDs: [id])
        #expect(projection.posts.map(\.id) == originalIDs)
        #expect(projection.posts.first?.liked == true)
        #expect(projection.posts.first?.createdAt == originalDate)
        #expect(projection.posts.first?.authorUserID == owner)
        projection.update(rows: [], names: [:], likedIDs: [id])
        #expect(projection.posts.isEmpty)
    }

    @Test func enrichmentAndEngagementDoNotReorderDisplayedPosts() throws {
        let owner = UUID().uuidString.lowercased()
        let idA = UUID().uuidString.lowercased()
        let idB = UUID().uuidString.lowercased()
        let date = ISO8601DateFormatter().string(from: Date())
        let a = WhisperPostRow(id: idA, user_id: owner, username: "layout_fixture", kind: "photo", caption: "First",
            symbol: nil, accent_hex: nil, media_count: 0, media_urls: [], is_ghost: false,
            is_reel: false, likes_count: 100, comments_count: 1, created_at: date, community_id: nil, community_name: nil)
        let b = WhisperPostRow(id: idB, user_id: owner, username: "layout_fixture", kind: "photo", caption: "Second",
            symbol: nil, accent_hex: nil, media_count: 0, media_urls: [], is_ghost: false,
            is_reel: false, likes_count: 0, comments_count: 0, created_at: date, community_id: nil, community_name: nil)
        let projection = WhisperFeedProjection()
        projection.update(rows: [a, b], names: [:], likedIDs: [])
        let order = projection.posts.map(\.id)
        let boosted = WhisperPostRow(id: idB, user_id: owner, username: "layout_fixture", kind: "photo", caption: "Second",
            symbol: nil, accent_hex: nil, media_count: 0, media_urls: [], is_ghost: false,
            is_reel: false, likes_count: 10000, comments_count: 1000, created_at: date, community_id: nil, community_name: nil)
        projection.update(rows: [boosted, a], names: [owner: "resolved_fixture"], likedIDs: [idB])
        #expect(projection.posts.map(\.id) == order)
        #expect(projection.posts.last?.likes == 10000)
        #expect(projection.posts.last?.liked == true)
        projection.update(rows: [boosted, a], names: [owner: "resolved_fixture"], likedIDs: [idB], forceRank: true)
        #expect(projection.posts.first?.id == UUID(uuidString: idB))
    }

    @Test func replySlotHasTheSameHeightBeforeAndAfterHydration() throws {
        let comment = WhisperCommentRow(id: UUID().uuidString, post_id: UUID().uuidString,
            user_id: UUID().uuidString, username: "fixture", body: String(repeating: "A long reply. ", count: 80),
            created_at: nil, parent_comment_id: nil, likes_count: 0)
        let empty = ImageRenderer(content: WhisperFeedReplyPreview(comment: nil, replyCount: 4, threadIndex: nil, threadCount: 0).frame(width: 320))
        let loaded = ImageRenderer(content: WhisperFeedReplyPreview(comment: comment, replyCount: 4, threadIndex: nil, threadCount: 0).frame(width: 320))
        let before = try #require(empty.uiImage)
        let after = try #require(loaded.uiImage)
        #expect(before.size == after.size)
    }

    @Test func measuredTileDoesNotChangeItsParentSize() throws {
        let renderer = ImageRenderer(content: Color.gray.frame(width: 120, height: 120)
            .overlay { WhisperSizedAsyncImage(url: nil) { _ in Color.orange }.allowsHitTesting(false) }
            .clipped())
        renderer.scale = 2
        let image = try #require(renderer.uiImage?.cgImage)
        #expect(image.width == 240 && image.height == 240)
    }
}
