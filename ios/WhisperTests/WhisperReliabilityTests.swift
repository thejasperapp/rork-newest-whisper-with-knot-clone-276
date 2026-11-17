import Testing
import Foundation
import UIKit
import SwiftUI
@testable import Whisper

struct WhisperReliabilityTests {
    @Test func masterPostStyleDoesNotDependOnEntryOrAvailableMedia() {
        #expect(WhisperPostPresentationPolicy.usesMediaCard(kind: .grid, isReel: false))
        #expect(WhisperPostPresentationPolicy.usesMediaCard(kind: .photo, isReel: true))
        for kind: WhisperPostKind in [.photo, .workout, .progress] {
            #expect(!WhisperPostPresentationPolicy.usesMediaCard(kind: kind, isReel: false))
        }
        #expect(WhisperPostPresentationPolicy.opensWavePlayer(isReel: true, commentID: nil, focusReply: false))
        #expect(!WhisperPostPresentationPolicy.opensWavePlayer(isReel: true, commentID: "reply", focusReply: false))
        #expect(!WhisperPostPresentationPolicy.opensWavePlayer(isReel: true, commentID: nil, focusReply: true))
    }

    @Test func openedPostMappingKeepsOriginalMetadataAndCarousel() throws {
        let caption = "::whisper-postmeta-v1::{\"location\":\"London\",\"tagged\":[\"friend\"],\"hideCounts\":true,\"commentsOff\":true}\nOriginal caption"
        let id = UUID()
        let row = WhisperPostRow(id: id.uuidString, user_id: UUID().uuidString, username: "author", kind: "grid",
            caption: caption, symbol: "photo", accent_hex: "#FFFFFF", media_count: 2,
            media_urls: ["https://example.com/one.jpg", "https://example.com/two.jpg"], is_ghost: false,
            is_reel: false, likes_count: 7, comments_count: 2, created_at: "2026-09-17T12:00:00Z",
            community_id: "community", community_name: "Running")
        let post = WhisperRootView.mapRowToPost(row)
        #expect(post.id == id && post.kind == .grid)
        #expect(post.mediaURLs.count == 2 && post.caption == caption)
        #expect(post.displayCaption == "Original caption")
        #expect(post.communityID == "community" && post.communityName == "Running")
        #expect(WhisperPostMeta.parse(from: post.caption)?.commentsOff == true)
        #expect(WhisperPostMeta.parse(from: post.caption)?.hideCounts == true)
    }

    @Test func profileVisibilityRequiresResolvedIdentityAndApprovedAccess() {
        #expect(!WhisperProfileVisibilityPolicy.canView(viewerID: "a", authorID: "b", resolved: false, isPrivate: nil, following: false, blocked: false))
        #expect(!WhisperProfileVisibilityPolicy.canView(viewerID: "a", authorID: "b", resolved: true, isPrivate: true, following: false, blocked: false))
        #expect(WhisperProfileVisibilityPolicy.canView(viewerID: "a", authorID: "b", resolved: true, isPrivate: true, following: true, blocked: false))
        #expect(!WhisperProfileVisibilityPolicy.canView(viewerID: "a", authorID: "b", resolved: true, isPrivate: false, following: true, blocked: true))
        #expect(WhisperProfileVisibilityPolicy.canView(viewerID: "A", authorID: "a", resolved: true, isPrivate: true, following: false, blocked: false))
        #expect(WhisperProfileTab.allCases.map(\.label) == ["Whisps", "Waves", "Replies", "Reposts", "Media"])
    }

    @Test func tabPreparationPrioritizesActualNeighbors() {
        #expect(WhisperRootTabSwipePolicy.prewarmOrder(from: 0) == [3, 1, 2, 4])
        #expect(WhisperRootTabSwipePolicy.prewarmOrder(from: 4) == [2, 1, 3, 0])
        #expect(Array(WhisperRootTabSwipePolicy.prewarmOrder(from: 1).prefix(2)) == [2, 3])
        for tab in WhisperRootTabSwipePolicy.order {
            let prepared = WhisperRootTabSwipePolicy.prewarmOrder(from: tab)
            #expect(prepared.count == 4 && Set(prepared).count == 4 && !prepared.contains(tab))
        }
    }

    @MainActor @Test func selectedInboxWingsKeepATransparentSeam() throws {
        for size: CGFloat in [22, 25] {
            for scale: CGFloat in [2, 3] {
                for dark in [false, true] {
                    let renderer = ImageRenderer(content: WhisperRoundedGlyph(size: size, selected: true)
                        .foregroundStyle(dark ? Color.white : Color.black))
                    renderer.scale = scale
                    let image = try #require(renderer.uiImage?.cgImage)
                    let seam = pixel(image, x: Int(size * scale * 0.48), y: Int(size * scale * 0.44))
                    let upperWing = pixel(image, x: Int(size * scale * 0.48), y: Int(size * scale * 0.23))
                    let lowerWing = pixel(image, x: Int(size * scale * 0.48), y: Int(size * scale * 0.70))
                    #expect(seam[3] < 40)
                    #expect(upperWing[3] > 240 && lowerWing[3] > 240)
                }
            }
        }
    }

    @MainActor @Test func incomingPageRendersContentDuringDragBeforeSelection() throws {
        let size = CGSize(width: 390, height: 300)
        for progress: CGFloat in [0.1, 0.5, 0.9] {
            let content = ZStack {
                Color.black
                Color.red.frame(width: size.width, height: size.height)
                    .modifier(WhisperTabPageMotion(progress: progress, moving: true, isSource: true, direction: 1,
                        restingOffset: 0, size: size, insets: EdgeInsets(), reduceMotion: false))
                VStack(spacing: 0) {
                    Color.green.frame(height: 100)
                    Color.blue.frame(height: 100)
                    Color.green.frame(height: 100)
                }
                .frame(width: size.width, height: size.height)
                .modifier(WhisperTabPageMotion(progress: progress, moving: true, isSource: false, direction: 1,
                    restingOffset: 1170, size: size, insets: EdgeInsets(), reduceMotion: false))
            }.frame(width: size.width, height: size.height).clipped()
            let renderer = ImageRenderer(content: content); renderer.scale = 1
            let image = try #require(renderer.uiImage?.cgImage)
            #expect(pixel(image, x: 380, y: 150)[2] > 240)
            #expect(pixel(image, x: 5, y: 150)[0] > 240)
        }
    }

    @MainActor @Test func storyBackgroundsRenderAtExactPixelsWithUprightOpaqueEdges() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.blue.setFill(); context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }
        let rotated = UIImage(cgImage: try #require(source.cgImage), scale: 1, orientation: .right)
        let size = CGSize(width: 108, height: 192)
        let blurred = try #require(WhisperWaveStoryBackground.blurred(from: rotated, size: size).cgImage)
        #expect(blurred.width == 108 && blurred.height == 192)
        let top = pixel(blurred, x: 54, y: 4)
        let bottom = pixel(blurred, x: 54, y: 187)
        #expect(top[0] > top[2])
        #expect(bottom[2] > bottom[0])
        for point in [(0, 0), (107, 0), (0, 191), (107, 191)] {
            #expect(pixel(blurred, x: point.0, y: point.1)[3] == 255)
        }
        let fallback = try #require(WhisperWaveStoryBackground.blurred(from: nil, size: size).cgImage)
        #expect(fallback.width == 108 && fallback.height == 192)
    }

    @MainActor @Test func sharedStoryExportUsesChosenColorPhotoOrOriginalBlur() throws {
        let original = WhisperWaveStoryBackground.render(top: .red, bottom: .red, size: CGSize(width: 108, height: 192))
        let photo = WhisperWaveStoryBackground.render(top: .blue, bottom: .blue, size: CGSize(width: 108, height: 192))
        for choice: WhisperStoryBackgroundSelection in [.blurred, .color("#00FF00"), .photo] {
            let renderer = ImageRenderer(content: WhisperSharedStoryBackdrop(original: original, selection: choice, photo: photo, size: CGSize(width: 1080, height: 1920)))
            renderer.scale = 1
            let cg = try #require(renderer.uiImage?.cgImage)
            #expect(cg.width == 1080 && cg.height == 1920)
            let color = pixel(cg, x: 540, y: 960)
            let channel = choice == .blurred ? 0 : (choice == .photo ? 2 : 1)
            #expect(color[channel] > 240)
            #expect(color[3] == 255)
            #expect(color[(channel + 1) % 3] < 12)
        }
    }

    @Test func sharedPostSizingPreservesAspectRatioAndLegacyStories() throws {
        var sticker = WhisperStorySticker(kind: .post)
        #expect(WhisperStoryPostCardLayout.size(sticker: sticker, stageWidth: 440) == CGSize(width: 250, height: 312))
        sticker.cardWidthFraction = 0.88; sticker.mediaAspectRatio = 0.75; sticker.mediaCount = 2
        sticker.postID = "original-post"; sticker.imageURL = "https://example.com/photo.jpg"
        for width: CGFloat in [320, 390, 440] {
            let size = WhisperStoryPostCardLayout.size(sticker: sticker, stageWidth: width)
            #expect(abs(size.width / size.height - 0.75) < 0.001)
            #expect(size.width <= width * 0.88 + 0.001)
            #expect(size.height <= width * 16 / 9 * 0.72 + 0.001)
        }
        let metadata = WhisperStoryMetadata(stickers: [sticker])
        #expect(WhisperStoryMetadata.decode(metadata.jsonString).stickers == [sticker])
        let old = WhisperStoryMetadata.decode("{\"stickers\":[{\"id\":\"old\",\"kind\":\"post\",\"x\":0.5,\"y\":0.47,\"scale\":1,\"rotation\":0}]}")
        #expect(old.stickers.first?.cardWidthFraction == nil)
        #expect(old.stickers.count == 1)
    }

    @Test func storyDraftRetainsBackgroundStickersAndDrawingWithoutBakingCard() throws {
        let sticker = WhisperStorySticker(kind: .post, postID: "original")
        let stroke = WhisperStoryDrawStroke(points: [.zero, CGPoint(x: 1, y: 1)], colorHex: "#FFFFFF", width: 7, marker: .pen)
        let draft = WhisperStoryDraftService.Draft(stickers: [sticker], savedAt: Date(), photoScale: 1,
            photoOffsetX: 0, photoOffsetY: 0, canvasWidth: 390, backgroundSelection: .photo,
            imageFilename: "blur.jpg", backgroundFilename: "chosen.jpg", drawStrokes: [stroke])
        let restored = try JSONDecoder().decode(WhisperStoryDraftService.Draft.self, from: JSONEncoder().encode(draft))
        #expect(restored.backgroundSelection == .photo)
        #expect(restored.stickers == [sticker])
        #expect(restored.imageFilename != restored.backgroundFilename)
        #expect(restored.drawStrokes == [stroke])
        let legacy = Data("{\"stickers\":[],\"savedAt\":0,\"photoScale\":1,\"photoOffsetX\":0,\"photoOffsetY\":0}".utf8)
        #expect(try JSONDecoder().decode(WhisperStoryDraftService.Draft.self, from: legacy).backgroundSelection == nil)
    }

    @MainActor private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeMutableBytes { buffer in
            if let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
        }
        let index = (y * image.width + x) * 4
        return Array(bytes[index..<(index + 4)])
    }

    @Test func accountRevealRequiresMatchingSessionAndRenderedDestination() {
        let generation = UUID()
        #expect(WhisperAccountTransitionPolicy.canReveal(expectedOwner: "Account-B", localOwner: "account-b", sessionOwner: "ACCOUNT-B", profileOwner: "account-b", expectedGeneration: generation, currentGeneration: generation, destinationGeneration: generation, active: true, signedIn: true))
        #expect(!WhisperAccountTransitionPolicy.canReveal(expectedOwner: "account-b", localOwner: "account-b", sessionOwner: "account-a", profileOwner: "account-b", expectedGeneration: generation, currentGeneration: generation, destinationGeneration: generation, active: true, signedIn: true))
        #expect(!WhisperAccountTransitionPolicy.canReveal(expectedOwner: "account-b", localOwner: "account-b", sessionOwner: "account-b", profileOwner: "account-a", expectedGeneration: generation, currentGeneration: generation, destinationGeneration: generation, active: true, signedIn: true))
        #expect(!WhisperAccountTransitionPolicy.canReveal(expectedOwner: "account-b", localOwner: "account-b", sessionOwner: "account-b", profileOwner: "account-b", expectedGeneration: generation, currentGeneration: generation, destinationGeneration: nil, active: true, signedIn: true))
    }

    @Test func accountRevealRejectsBackgroundSignOutAndStaleGeneration() {
        let generation = UUID()
        #expect(!WhisperAccountTransitionPolicy.canReveal(expectedOwner: "b", localOwner: "b", sessionOwner: "b", profileOwner: "b", expectedGeneration: generation, currentGeneration: UUID(), destinationGeneration: generation, active: true, signedIn: true))
        #expect(!WhisperAccountTransitionPolicy.canReveal(expectedOwner: "b", localOwner: "b", sessionOwner: "b", profileOwner: "b", expectedGeneration: generation, currentGeneration: generation, destinationGeneration: generation, active: false, signedIn: true))
        #expect(!WhisperAccountTransitionPolicy.canReveal(expectedOwner: "b", localOwner: "b", sessionOwner: nil, profileOwner: "b", expectedGeneration: generation, currentGeneration: generation, destinationGeneration: generation, active: true, signedIn: false))
    }

    @Test func avatarCacheKeysKeepSizesAndSignedURLsSeparate() throws {
        let first = try #require(URL(string: "https://example.com/avatar.jpg?token=first"))
        let second = try #require(URL(string: "https://example.com/avatar.jpg?token=second"))
        #expect(WhisperImageCache.key(first) != WhisperImageCache.key(first, maxPixelSize: 128))
        #expect(WhisperImageCache.key(first, maxPixelSize: 128) != WhisperImageCache.key(first, maxPixelSize: 256))
        #expect(WhisperImageCache.key(first, maxPixelSize: 128) != WhisperImageCache.key(second, maxPixelSize: 128))
    }

    @MainActor @Test func avatarDecoderDownsamplesWithoutShrinkingViewerImages() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800), format: format).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        let data = try #require(source.pngData())
        let thumbnail = try #require(WhisperImageCache.decode(data, maxPixelSize: 128)?.cgImage)
        #expect(thumbnail.width == 128)
        #expect(thumbnail.height <= 86)
        let full = try #require(WhisperImageCache.decode(data, maxPixelSize: nil)?.cgImage)
        #expect(full.width == 1200 && full.height == 800)
        #expect(WhisperImageCache.decode(Data([1, 2, 3]), maxPixelSize: 128) == nil)
    }

    @Test func enlargedPhotosReserveHorizontalTravelForPaging() {
        #expect(!WhisperPhotoPagingPolicy.isVertical(CGSize(width: 180, height: 18)))
        #expect(!WhisperPhotoPagingPolicy.isVertical(CGSize(width: 80, height: 80)))
        #expect(WhisperPhotoPagingPolicy.isVertical(CGSize(width: 18, height: 180)))
        #expect(WhisperPhotoPagingPolicy.index(2, count: 4) == 2)
        #expect(WhisperPhotoPagingPolicy.index(-1, count: 4) == 0)
        #expect(WhisperPhotoPagingPolicy.index(20, count: 4) == 3)
        #expect(WhisperPhotoPagingPolicy.index(0, count: 0) == nil)
    }

    @Test func photoPanningStaysWithinFittedImageBounds() {
        let proposed = CGSize(width: 900, height: -900)
        let image = CGSize(width: 1200, height: 800)
        let viewport = CGSize(width: 400, height: 800)
        #expect(WhisperPhotoPagingPolicy.clamp(proposed, image: image, viewport: viewport, scale: 1) == .zero)
        #expect(WhisperPhotoPagingPolicy.clamp(proposed, image: image, viewport: viewport, scale: 2) == CGSize(width: 200, height: 0))
    }

    @Test func navigationNeverDimsPredecessorContent() {
        for progress: CGFloat in [0, 0.1, 0.5, 0.9, 1] {
            #expect(WhisperBackRevealStyle.scrim(progress: progress) == 0)
        }
    }

    @Test func jasperWaitingLabelsDoNotInventToolActivity() {
        for query in ["latest news", "paint an image", "my sleep", "make a plan"] {
            let labels = WhisperEmberThinkingSteps.stepLabels(isAnalytical: false, queryHint: query, resolvedLabel: nil)
            #expect(labels == ["Thinking"])
        }
        #expect(WhisperEmberThinkingSteps.stepLabels(isAnalytical: true, queryHint: nil, resolvedLabel: "Weekly steps") == ["Weekly steps"])
    }

    @MainActor @Test func navigationSnapshotRejectsAnUnownedAccount() {
        let store = WhisperNavigationSnapshots()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        store.capture(view, account: UUID())
        #expect(store.image(for: view) == nil)
        store.clear()
        #expect(store.image(for: view) == nil)
    }

    @MainActor @Test func detachedTransitionCoverRemainsImmediatelyRemovable() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let cover = WhisperTransitionCover(frame: window.bounds)
        window.addSubview(cover)
        #expect(cover.superview === window)
        cover.clearForInterruption()
        #expect(cover.superview == nil)
        cover.clearForInterruption()
        #expect(cover.superview == nil)
    }

    @Test func failedGroupMessagesKeepIndependentIdentityAndReplyBody() throws {
        let first = WhisperFailedChatMessage(id: UUID(), body: "Reply quote and message")
        let second = WhisperFailedChatMessage(id: UUID(), body: "Reply quote and message")
        let encoded = try JSONEncoder().encode([first, second])
        let restored = try JSONDecoder().decode([WhisperFailedChatMessage].self, from: encoded)
        #expect(restored == [first, second])
        #expect(restored[0].id != restored[1].id)
    }

    @Test func tabPagesTravelTogetherWithReferenceGutterAndNoOverlap() {
        let samples: [CGFloat] = [0, 0.1, 0.5, 0.9, 1]
        for direction in [-1, 1] {
            for progress in samples {
                let source = WhisperTabPagingState.offset(isSource: true, direction: direction, progress: progress, width: 390)
                let target = WhisperTabPagingState.offset(isSource: false, direction: direction, progress: progress, width: 390)
                #expect(abs(abs(target - source) - 402) < 0.001)
                if progress == 1 { #expect(target == 0) }
                if progress == 0 { #expect(source == 0) }
            }
        }
    }

    @Test func tabCornersRemainRoundedThroughSlowDragAndSettle() {
        for progress: CGFloat in [0.08, 0.25, 0.5, 0.75, 0.92] {
            #expect(WhisperTabPagingState.cornerRadius(progress: progress, width: 390) == 52)
        }
        #expect(WhisperTabPagingState.cornerRadius(progress: 0, width: 390) == 0)
        #expect(WhisperTabPagingState.cornerRadius(progress: 1, width: 390) == 0)
        #expect(WhisperTabPagingState.cornerRadius(progress: .nan, width: 390) == 0)
        #expect(WhisperTabPagingState.stride(width: .infinity) == 0)
    }

    @MainActor @Test func pagerFollowsFingerAndRejectsConcurrentGestures() {
        let pager = WhisperTabPagingState()
        #expect(pager.begin(selection: 2, direction: -1) == 1)
        pager.update(translation: 201, width: 390)
        #expect(pager.progress == 0.5)
        #expect(pager.source == 2 && pager.target == 1)
        #expect(pager.begin(selection: 2, direction: 1) == nil)
        pager.update(translation: -20, width: 390)
        #expect(pager.progress == 0)
        pager.reset()
        #expect(pager.source == nil && pager.target == nil && !pager.isSettling)
        #expect(pager.begin(selection: 0, direction: -1) == nil)
    }

    @MainActor @Test func pagerCancellationDoesNotSelectNeighbor() async {
        let pager = WhisperTabPagingState()
        _ = pager.begin(selection: 0, direction: 1)
        pager.update(translation: -100, width: 390)
        let result: Int? = await withCheckedContinuation { continuation in
            pager.settle(commit: false, velocity: 0, reduceMotion: true) { continuation.resume(returning: $0) }
        }
        #expect(result == nil)
        #expect(pager.source == nil && pager.progress == 0)
    }

    @Test func ordinaryBackPredecessorRemainsStationary() {
        #expect(WhisperBackRevealStyle.predecessorOffset(width: 400, progress: 0) == 0)
        #expect(WhisperBackRevealStyle.predecessorOffset(width: 400, progress: 0.5) == 0)
        #expect(WhisperBackRevealStyle.predecessorOffset(width: 400, progress: 1) == 0)
        #expect(WhisperBackRevealStyle.predecessorOffset(width: .infinity, progress: 0.5) == 0)
    }

    @MainActor @Test func arrowAndCommittedGestureDoNotDoubleAnimate() {
        let back = WhisperBackAction()
        var animations = 0
        var commits = 0
        back.animate = { action in animations += 1; back.commit(action) }
        back.perform { commits += 1 }
        #expect(animations == 1 && commits == 1)
        back.commit { back.perform { commits += 1 } }
        #expect(animations == 1 && commits == 2)
    }

    @Test func jasperMentionsRequireWholeHandles() {
        #expect(WhisperEmberMention.shouldRespond(to: "@Jasper hello"))
        #expect(WhisperEmberMention.shouldRespond(to: "Help, @ember!"))
        #expect(!WhisperEmberMention.shouldRespond(to: "@jasperfan hello"))
        #expect(!WhisperEmberMention.shouldRespond(to: "@ember_test hello"))
        #expect(!WhisperEmberMention.shouldRespond(to: "user@jasper.example"))
    }

    @MainActor @Test func localBackCoverCleansUpWithoutDismissingHost() async throws {
        let front = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: front.bounds)
        let controller = UIViewController(); controller.view = front
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        // Handoff tests start with a valid cached snapshot, as local routes do.
        let image = UIGraphicsImageRenderer(size: front.bounds.size).image { context in
            UIColor.blue.setFill(); context.fill(front.bounds)
        }
        let back = UIImageView(image: image); back.frame = front.bounds
        window.insertSubview(back, belowSubview: front)
        let reveal = try #require(WhisperBackRevealSession(surface: front, predecessor: back, localTransition: true))
        let completed = await withCheckedContinuation { continuation in
            reveal.settle(leaving: true) { continuation.resume(returning: $0) }
        }
        #expect(completed)
        let deadline = Date().addingTimeInterval(1)
        while window.subviews.contains(where: { $0 !== front && $0.accessibilityElementsHidden }), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(front.window === window)
        #expect(!window.subviews.contains(where: { $0 !== front && $0.accessibilityElementsHidden }))
    }

    @Test func tabSwipesFollowVisibleOrderAndNeverWrap() {
        #expect(WhisperRootTabSwipePolicy.destination(selection: 0, dx: -90, dy: 3, velocity: -300) == 3)
        #expect(WhisperRootTabSwipePolicy.destination(selection: 3, dx: -90, dy: 3, velocity: -300) == 1)
        #expect(WhisperRootTabSwipePolicy.destination(selection: 2, dx: -90, dy: 3, velocity: -300) == 4)
        #expect(WhisperRootTabSwipePolicy.destination(selection: 2, dx: 90, dy: 3, velocity: 300) == 1)
        #expect(WhisperRootTabSwipePolicy.destination(selection: 4, dx: -90, dy: 3, velocity: -300) == nil)
        #expect(WhisperRootTabSwipePolicy.destination(selection: 0, dx: 90, dy: 3, velocity: 300) == nil)
        #expect(WhisperRootTabSwipePolicy.destination(selection: 2, dx: 30, dy: 100, velocity: 900) == nil)
    }

    @Test func groupCallDescriptorPreservesIdentityAndMode() throws {
        let call = WhisperGroupCallDescriptor(callID: UUID().uuidString, roomID: UUID().uuidString, groupID: UUID().uuidString, groupName: "Weekend", mode: .audio)
        #expect(WhisperGroupCallDescriptor.decode(call.encoded) == call)
        let row = WhisperMeetingRow(id: call.roomID, host_id: "host", host_username: "alex", title: "Group call · Weekend", status: "live", scheduled_at: nil, started_at: nil, ended_at: nil, summary: call.encoded, created_at: nil)
        #expect(row.isGroupCall)
        #expect(row.groupCall?.mode == .audio)
        #expect(row.groupCall?.callID != row.groupCall?.roomID)
        #expect(WhisperGroupCallDescriptor.decode("Ordinary meeting notes") == nil)
        #expect(WhisperGroupCallDescriptor.decode(WhisperGroupCallDescriptor.prefix + "{}") == nil)
    }

    @Test func puppyTongueFollowsMouthOpeningWithoutHardPop() {
        #expect(WhisperARProcessor.puppyTongueAmount(opening: 0) == 0)
        #expect(WhisperARProcessor.puppyTongueAmount(opening: 0.04) == 0)
        #expect(WhisperARProcessor.puppyTongueAmount(opening: 0.125) > 0.4)
        #expect(WhisperARProcessor.puppyTongueAmount(opening: 0.125) < 0.6)
        #expect(WhisperARProcessor.puppyTongueAmount(opening: 0.3) == 1)
    }

    @Test func storiesUseTheSameFaceDefaultsAndPreviewRecipe() {
        let effects = WhisperStoryCaptureEffects(effect: .puppy)
        #expect(effects.face.kind == .puppy)
        #expect(effects.face.amount == 1)
        #expect(effects.configuration.face == effects.face)
        #expect(effects.configuration.cameraEffect == .puppy)
        #expect(WhisperStoryCaptureEffects(effect: .bigEyes).face.amount == 0.35)
    }

    @Test func accessoryIconsUseTheSharedIllustratedArtwork() throws {
        for effect in [WhisperAREffect.puppy, .bunny, .sunnies, .halo] {
            let icon = try #require(WhisperARProcessor.shared.accessoryIcon(effect))
            #expect(icon.width == 240)
            #expect(icon.height == 240)
        }
        #expect(WhisperARProcessor.shared.accessoryIcon(.none) == nil)
    }

    @MainActor @Test func leavingRevealKeepsDestinationVisibleThroughDismissal() async throws {
        let front = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: front.bounds)
        let controller = UIViewController(); controller.view = front
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        front.backgroundColor = .white
        // Handoff tests start with a valid cached snapshot, as local routes do.
        let image = UIGraphicsImageRenderer(size: front.bounds.size).image { context in
            UIColor.blue.setFill(); context.fill(front.bounds)
        }
        let back = UIImageView(image: image); back.frame = front.bounds
        window.insertSubview(back, belowSubview: front)
        let reveal = try #require(WhisperBackRevealSession(surface: front, predecessor: back))
        reveal.update(translation: 240)
        let didCoverDismissal = await withCheckedContinuation { continuation in
            reveal.settle(leaving: true, velocity: 500) { valid in
                let covered = window.subviews.contains { $0 !== front && $0.accessibilityElementsHidden }
                front.removeFromSuperview()
                continuation.resume(returning: valid && covered)
            }
        }
        #expect(didCoverDismissal)
    }

    @Test func selectedAccessoriesAreOpaqueWithoutStrengtheningDistortions() {
        var setting = WhisperWaveFaceSetting(amount: 0.35, smoothing: 0.2)
        for kind in [WhisperWaveFaceSetting.Kind.puppy, .halo, .bunny, .sunnies] {
            setting.select(kind)
            #expect(setting.amount == 1)
            #expect(setting.smoothing == 0.2)
        }
        setting.amount = 0.7
        setting.select(.sunnies)
        #expect(setting.amount == 0.7)
        setting.select(.bigEyes)
        #expect(setting.amount == 0.35)
    }

    @Test func pushInvitesPreserveGroupRoomRecipientAndAge() throws {
        let id = "85e52de7-890e-46fd-bb06-1a4fcdb4fa48"
        let invite = try #require(WhisperCallSignal.pushInvite([
            "call_id": "call", "from_user_id": "sender", "from_username": "alex", "mode": "audio",
            "group_id": id, "group_name": "Weekend", "meeting_id": "room", "recipient_user_id": "recipient", "at": "123"
        ]))
        #expect(invite.groupId == id)
        #expect(invite.groupName == "Weekend")
        #expect(invite.mode == .audio)
        #expect(invite.roomID == "room")
        #expect(invite.toUserId == "recipient")
        #expect(invite.at == 123)
        #expect(WhisperCallSignal.pushInvite(["call_id": "bad"]) == nil)
    }

    @Test func backRevealUsesStoriesRoundingAndClampedProgress() {
        #expect(WhisperBackRevealStyle.progress(translation: 195, width: 390) == 0.5)
        #expect(WhisperBackRevealStyle.progress(translation: -90, width: 390) == 0)
        #expect(WhisperBackRevealStyle.progress(translation: 800, width: 390) == 1)
        #expect(WhisperBackRevealStyle.progress(translation: 20, width: 0) == 0)
        #expect(WhisperBackRevealStyle.radius(topInset: 59, progress: 0) == 0)
        #expect(WhisperBackRevealStyle.radius(topInset: 59, progress: 0.5) == 55)
        #expect(WhisperBackRevealStyle.scrim(progress: 0.5) == 0)
    }

    @MainActor @Test func compactTabBarKeepsFullSizeTouchRow() {
        #expect(WhisperTabBarMetrics.barHeight == 48.5)
        #expect(WhisperTabBarMetrics.barHeight - 0.5 - 2 * WhisperTabBarMetrics.verticalPadding == 44)
    }

    @MainActor @Test func nativePopCannotBypassNestedGuardsAndRestoresAfterRelease() {
        let nav = UINavigationController(rootViewController: UIViewController())
        nav.loadViewIfNeeded()
        nav.interactivePopGestureRecognizer?.isEnabled = true
        let outer = WhisperNavigationGestureLease()
        let inner = WhisperNavigationGestureLease()
        outer.acquire(nav); inner.acquire(nav)
        #expect(nav.interactivePopGestureRecognizer?.isEnabled == false)
        outer.release()
        #expect(nav.interactivePopGestureRecognizer?.isEnabled == false)
        inner.release()
        #expect(nav.interactivePopGestureRecognizer?.isEnabled == true)
    }

    @MainActor @Test func cancelledRevealClearsOverlayAndNeverAuthorizesExit() throws {
        let front = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: front.bounds)
        let controller = UIViewController(); controller.view = front
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        front.layoutIfNeeded()
        front.backgroundColor = .white
        // Handoff tests start with a valid cached snapshot, as local routes do.
        let image = UIGraphicsImageRenderer(size: front.bounds.size).image { context in
            UIColor.blue.setFill(); context.fill(front.bounds)
        }
        let back = UIImageView(image: image); back.frame = front.bounds
        window.insertSubview(back, belowSubview: front)
        let reveal = try #require(WhisperBackRevealSession(surface: front, predecessor: back))
        #expect(front.subviews.count == 1)
        #expect(front.subviews.last?.isUserInteractionEnabled == true)
        reveal.update(translation: 180)
        var result: Bool?
        reveal.settle(leaving: true) { result = $0 }
        reveal.remove()
        #expect(result == false)
        #expect(front.subviews.isEmpty)
        #expect(front.transform == .identity)
        reveal.remove()
        #expect(result == false)
    }

    @Test func groupPreviewsKeepIdentityButNeverWirePayloads() throws {
        let id = "85e52de7-890e-46fd-bb06-1a4fcdb4fa48"
        let raw = "::wg-v1::\(id)::Weekend plans::::whisper-post-v1::{\"caption\":\"escaped } braces\"}"
        let group = try #require(WhisperMessagePreview.group(raw))
        #expect(group.id.uuidString.lowercased() == id)
        #expect(group.name == "Weekend plans")
        #expect(WhisperMessagePreview.text(raw) == "Shared a post")
    }
    @Test func malformedAndNestedMessagesFailClosed() {
        for raw in ["::wg-v1::invalid::Group::{secret}", "::whisper-future-v9::{\"value\":\"} secret\"}", "caption ::whisper-photo-v1::{broken", "{\"raw\":true}", "[1,2,3]"] {
            let preview = WhisperMessagePreview.text(raw)
            #expect(!preview.contains("::"))
            #expect(!preview.contains("secret"))
            #expect(!preview.contains("{"))
        }
        let nested = "::wg-v1::85e52de7-890e-46fd-bb06-1a4fcdb4fa48::Name::::wg-v1::invalid"
        #expect(WhisperMessagePreview.text(nested) == "New message")
        #expect(WhisperMessagePreview.text(String(repeating: "a", count: 300_000)) == "New message")
    }
    @Test func normalPreviewsAreReadableAndBounded() {
        #expect(WhisperMessagePreview.text(" Meet at six\nby the cafe ") == "Meet at six by the cafe")
        #expect(WhisperMessagePreview.text(String(repeating: "a", count: 200)).count == 180)
        #expect(WhisperMessagePreview.text("jasper-sticker://example") == "Sent a sticker")
    }
    @Test func backRequiresPhysicalLeftEdgeAndRightwardIntent() {
        #expect(WhisperEdgeBackPolicy.commits(startX: 0, dx: 90, dy: 8, velocityX: 100))
        #expect(WhisperEdgeBackPolicy.commits(startX: 24, dx: 30, dy: 4, velocityX: 700))
        #expect(!WhisperEdgeBackPolicy.commits(startX: 25, dx: 200, dy: 0, velocityX: 1000))
        #expect(!WhisperEdgeBackPolicy.commits(startX: 180, dx: 200, dy: 0, velocityX: 1000))
        #expect(!WhisperEdgeBackPolicy.commits(startX: 0, dx: -100, dy: 0, velocityX: -800))
        #expect(!WhisperEdgeBackPolicy.commits(startX: 0, dx: 90, dy: 100, velocityX: 800))
        #expect(!WhisperEdgeBackPolicy.commits(startX: 0, dx: 20, dy: 0, velocityX: 900))
    }
    @MainActor @Test func widgetRoutesKeepStableIdentityAndImagineDestination() throws {
        let store = WhisperExternalRouteStore()
        let url = try #require(URL(string: "whisper://dm/renamed?uid=85e52de7-890e-46fd-bb06-1a4fcdb4fa48&owner=account-a"))
        store.enqueue(url: url)
        #expect(store.pending?.userID == "85e52de7-890e-46fd-bb06-1a4fcdb4fa48")
        #expect(store.pending?.owner == "account-a")
        store.accountWillChange()
        #expect(store.pending == nil)
        store.enqueue(url: try #require(URL(string: "whisper://imagine")))
        #expect(store.pending?.kind == "imagine")
    }
    @MainActor @Test func unboundColdLaunchRequestSurvivesLogin() {
        let store = WhisperExternalRouteStore()
        store.enqueue(.init(kind: "stories"))
        store.accountWillChange()
        #expect(store.pending?.kind == "stories")
        #expect(store.enqueue(notification: ["kind": "whisper_group", "groupID": "group-id", "recipientUID": "account-b"]))
        #expect(store.pending?.kind == "group")
        #expect(store.pending?.owner == "account-b")
        store.accountWillChange(to: "account-b")
        #expect(store.pending?.kind == "group")
        store.accountWillChange(to: "account-c")
        #expect(store.pending == nil)
    }
    @Test func staleWidgetWritersCannotRestorePreviousAccountContent() throws {
        let suite = "whisper.test.snapshot.\(UUID().uuidString)"
        let raw = try #require(UserDefaults(suiteName: suite))
        defer { raw.removePersistentDomain(forName: suite) }
        raw.set("account-a-epoch", forKey: "whisper_snapshot_epoch")
        let old = try #require(WhisperWidgetSnapshotDefaults(suiteName: suite))
        old.set("private A", forKey: "whisper_last_preview")
        raw.set("account-b-epoch", forKey: "whisper_snapshot_epoch")
        let current = try #require(WhisperWidgetSnapshotDefaults(suiteName: suite))
        old.set("late A", forKey: "whisper_last_preview")
        #expect(current.string(forKey: "whisper_last_preview") == nil)
        current.set("B", forKey: "whisper_last_preview")
        old.removeObject(forKey: "whisper_last_preview")
        #expect(current.string(forKey: "whisper_last_preview") == "B")
        #expect(old.string(forKey: "whisper_last_preview") == nil)
    }
}
