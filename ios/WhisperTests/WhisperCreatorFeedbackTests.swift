import Testing
import Foundation
import CoreGraphics
import UIKit
@testable import Whisper

struct WhisperCreatorFeedbackTests {
    @Test func storyMusicSectionIsBoundedAndPersistsWithoutStickers() throws {
        let slice = WhisperStoryMusicSelection(startSeconds: 26, durationSeconds: 12, availableDuration: 30)
        #expect(slice.startSeconds == 18)
        #expect(slice.durationSeconds == 12)
        let raw = try #require(WhisperStoryMetadata(musicSelection: slice).jsonString)
        let decoded = WhisperStoryMetadata.decode(raw)
        #expect(decoded.musicSelection == slice)
        #expect(WhisperStoryMetadata.decode("{\"stickers\":[]}").musicSelection == nil)
        let short = WhisperStoryMusicSelection(startSeconds: 9, durationSeconds: 7, availableDuration: 2)
        #expect(short.startSeconds == 0 && short.durationSeconds == 2)
        let song = WhisperStoryMusic(id: "preview", title: "Song", artist: "Artist", artworkURL: nil, previewURL: "https://example.com/preview.m4a", startSeconds: 45, durationSeconds: 7, previewDuration: 90)
        #expect(song.storySelection?.startSeconds == 45)
        #expect(song.storySelection?.durationSeconds == 7)
    }

    @Test func enlargedStoryPhotoRemainsPositionedOnRelease() {
        let offset = CGSize(width: 30, height: -45)
        let bounded = WhisperStoryPhotoGeometry.boundedOffset(offset, scale: 1.5, image: CGSize(width: 1080, height: 1920), stage: CGSize(width: 390, height: 693))
        #expect(bounded == offset)
        let unreachable = WhisperStoryPhotoGeometry.boundedOffset(CGSize(width: 5000, height: -5000), scale: 1.5, image: CGSize(width: 1080, height: 1920), stage: CGSize(width: 390, height: 693))
        #expect(unreachable.width < 100 && unreachable.height > -174)
    }

    @MainActor @Test func groupMissedCallsKeepTheirConversationIdentity() {
        let store = WhisperExternalRouteStore()
        let group = UUID().uuidString
        let owner = UUID().uuidString
        #expect(store.enqueue(notification: ["kind": "whisper_missed_call", "groupID": group, "recipientUID": owner, "fromUID": UUID().uuidString]))
        #expect(store.pending?.kind == "group")
        #expect(store.pending?.userID == group)
        #expect(store.pending?.owner == owner.lowercased())
    }

    @MainActor @Test func downwardRevealStaysOnTheVerticalAxis() throws {
        let surface = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let image = UIGraphicsImageRenderer(size: surface.bounds.size).image { context in
            UIColor.white.setFill(); context.fill(surface.bounds)
        }
        let predecessor = UIImageView(image: image)
        predecessor.frame = surface.bounds
        let session = try #require(WhisperBackRevealSession(surface: surface, predecessor: predecessor, vertical: true))
        session.update(translation: 140)
        let card = try #require(surface.subviews.last?.subviews.last)
        #expect(abs(card.transform.tx) < 0.01)
        #expect(abs(card.transform.ty - 140) < 0.01)
        session.remove()
        #expect(surface.subviews.isEmpty)
    }

    @Test func cameraPreviewPreservesTwentyFourFrameCadence() {
        for inputRate in [24, 30, 60] {
            var cadence = WhisperCameraFrameCadence()
            var admitted = 0
            for frame in 0..<(inputRate * 10) {
                if cadence.admits(Double(frame) / Double(inputRate)) { admitted += 1 }
            }
            #expect(admitted == 240)
            let afterPause = cadence.admits(20)
            let repeatedTime = cadence.admits(20)
            let restarted = cadence.admits(1)
            let invalidTime = cadence.admits(.nan)
            #expect(afterPause)
            #expect(!repeatedTime)
            #expect(restarted)
            #expect(!invalidTime)
        }
    }

    @Test func visibleStoryTextWinsOverNeighborTouchPadding() {
        let text = WhisperStoryHitRegion(id: "text", center: CGPoint(x: 50, y: 50), size: CGSize(width: 24, height: 20), scale: 1, rotation: 0)
        let tiny = WhisperStoryHitRegion(id: "tiny", center: CGPoint(x: 24, y: 50), size: CGSize(width: 4, height: 4), scale: 1, rotation: 0)
        #expect(WhisperStoryHitRegion.target(at: CGPoint(x: 44, y: 50), regions: [text, tiny]) == "text")
        #expect(WhisperStoryHitRegion.target(at: CGPoint(x: 24, y: 50), regions: [text, tiny]) == "tiny")
        #expect(WhisperStoryHitRegion.target(at: CGPoint(x: 1000, y: 1000), regions: [text, tiny]) == nil)
        let overlay = WhisperStoryHitRegion(id: "front", center: text.center, size: text.size, scale: 2, rotation: .pi / 4)
        #expect(WhisperStoryHitRegion.target(at: text.center, regions: [text, overlay]) == "front")
    }

    @MainActor @Test func firstStoryTouchOwnsAllRecognizersAndCancellationIsNotDeletion() {
        var begins: [StoryGestureTarget] = []
        var ends: [StoryGestureTarget] = []
        var cancellations: [StoryGestureTarget] = []
        let overlay = StoryStageGestureOverlay(hitTest: { $0.x < 100 ? "first" : "second" },
            onBegin: { begins.append($0) }, onPan: { _, _ in }, onPinch: { _, _, _ in }, onRotate: { _, _, _ in },
            onEnd: { target, _ in ends.append(target) }, onCancel: { target, _ in cancellations.append(target) }, onTap: { _ in }, onLongPress: { _ in })
        let coordinator = overlay.makeCoordinator()
        let pan = UIPanGestureRecognizer(); let pinch = UIPinchGestureRecognizer()
        coordinator.beginTouches(at: CGPoint(x: 20, y: 20))
        coordinator.recognizerBegan(pan, at: CGPoint(x: 180, y: 20))
        coordinator.recognizerBegan(pinch, at: CGPoint(x: 240, y: 20))
        coordinator.recognizerEnded(pinch)
        #expect(ends.isEmpty)
        coordinator.finishTouches(cancelled: true)
        coordinator.finishTouches(cancelled: false)
        #expect(begins == [.sticker("first")])
        #expect(cancellations == [.sticker("first")])
        #expect(ends.isEmpty)
        coordinator.beginTouches(at: CGPoint(x: 200, y: 20))
        coordinator.recognizerBegan(pan, at: .zero)
        coordinator.finishTouches(cancelled: false)
        #expect(ends == [.sticker("second")])
    }

    @Test func shortIntentionalBackSwipesCommitButReversalsAndInteriorSwipesDoNot() {
        #expect(WhisperEdgeBackPolicy.commits(startX: 12, dx: 54, dy: 30, velocityX: 0))
        #expect(WhisperEdgeBackPolicy.commits(startX: 24, dx: 24, dy: 4, velocityX: 420))
        #expect(!WhisperEdgeBackPolicy.commits(startX: 25, dx: 100, dy: 0, velocityX: 900))
        #expect(!WhisperEdgeBackPolicy.commits(startX: 0, dx: 70, dy: 0, velocityX: -300))
        #expect(!WhisperEdgeBackPolicy.commits(startX: 0, dx: 20, dy: 0, velocityX: 900))
    }

    @Test func bioDisplayRemovesTagPrefixesWithoutChangingURLsOrWords() {
        #expect(WhisperProfileBioView.displayBio("#Fitness #Café\n#Running") == "Fitness Café\nRunning")
        #expect(WhisperProfileBioView.displayBio("C# and https://example.com/#section") == "C# and https://example.com/#section")
    }

    @MainActor @Test func unavailableInsightsAreNotZeroOrEstimated() {
        let unavailable = WhisperPostInsightsSnapshot(likes: 12, comments: nil, views: nil)
        #expect(unavailable.likes == 12)
        #expect(unavailable.views == nil)
        #expect(unavailable.comments == nil)
        #expect(unavailable.engagementRate == 0)
        #expect(WhisperPostInsightsSnapshot(likes: 10, comments: 2, views: 100).engagementRate == 0.12)
    }

    @Test func quotedPostTokenPreservesReferenceAndSeparatesCommentary() {
        let id = UUID().uuidString.lowercased()
        let token = WhisperSharedPostEmbed.encode(.init(postID: id, username: "author", caption: "", kindRaw: "grid", symbol: "photo", accentHex: nil, mediaURL: nil, isVideo: false, likes: 1, comments: 2))
        let parsed = WhisperContentEmbedParser.parse("My commentary\n\n" + token)
        #expect(parsed.cleaned == "My commentary")
        #expect(parsed.quote?.postID == id)
        #expect(parsed.quote?.mediaURL == nil)
        #expect(WhisperContentEmbedParser.parse("::whisper-sharedpost-v1::broken").cleaned.isEmpty)
    }

    @Test func displayNamesMatchWithoutBecomingUserIdentity() {
        #expect(WhisperUserSearch.matches("jose rivera", username: "runner92", displayName: "José Rivera"))
        #expect(WhisperUserSearch.matches("@runner", username: "runner92", displayName: nil))
        #expect(!WhisperUserSearch.matches("rivera", username: "runner92", displayName: nil))
    }

    @Test func eyeBasisDoesNotFlipPastVertical() throws {
        for degrees in [0.0, 45, 89, 91, 135, 179, -91] {
            let a = degrees * .pi / 180
            let left = CGPoint(x: 120-cos(a)*30, y: 120-sin(a)*30)
            let right = CGPoint(x: 120+cos(a)*30, y: 120+sin(a)*30)
            let mouth = CGPoint(x: 120+sin(a)*55, y: 120-cos(a)*55)
            let basis = try #require(WhisperFaceBasis(left: left, right: right, mouth: mouth))
            #expect(abs(basis.distance - 60) < 0.001)
            #expect(abs(basis.up.dx + sin(a)) < 0.001)
            #expect(abs(basis.up.dy - cos(a)) < 0.001)
        }
        #expect(WhisperFaceBasis(left: .zero, right: .zero, mouth: .zero) == nil)
    }

    @Test func poseTrackingDropsLostFacesAndUnwrapsAngles() throws {
        let tracker = WhisperFacePoseTracker()
        func frame(_ angle: CGFloat) -> WhisperARProcessor.FaceFrame {
            .init(eyeMid: CGPoint(x: 100,y: 100), eyeDistance: 45, angle: angle, up: CGVector(dx: -sin(angle),dy:cos(angle)), faceWidth: 100, faceHeight: 140, noseTip: CGPoint(x: 100,y: 80), mouth: CGPoint(x:100,y:60), mouthOpening:0.1)
        }
        _ = tracker.update([frame(.pi - 0.01)], time: 1)
        let next = try #require(tracker.update([frame(-.pi + 0.01)], time: 1.04).first)
        #expect(abs(abs(next.angle) - .pi) < 0.02)
        #expect(tracker.update([], time:1.08).isEmpty)
        let fresh = try #require(tracker.update([frame(0)],time:1.12).first)
        #expect(fresh.angle == 0)
    }

    @Test func tabletBreakpointsMatchWebWithoutChangingPhoneWidths() {
        let portrait = WhisperTabletLayout(width:834,isPad:true,fullBleed:false)
        #expect(portrait.contentWidth == 640 && !portrait.hasSidebar && portrait.hasBottomBar)
        let landscape = WhisperTabletLayout(width:1194,isPad:true,fullBleed:false)
        #expect(landscape.hasSidebar && !landscape.hasRightRail && !landscape.hasBottomBar && landscape.contentWidth == 640)
        #expect(WhisperTabletLayout(width:1366,isPad:true,fullBleed:false).hasRightRail)
        #expect(WhisperTabletLayout(width:390,isPad:false,fullBleed:false).contentWidth == 390)
        #expect(WhisperTabletLayout(width:1366,isPad:true,fullBleed:true).contentWidth == 1366)
    }

    @Test func malformedThemeKeepsRevisionForRecovery() throws {
        let id = UUID()
        let raw = "{\"group_id\":\"\(id)\",\"revision\":7,\"theme\":{\"version\":\"1\"}}"
        let record = try JSONDecoder().decode(WhisperGroupThemeRecord.self,from:Data(raw.utf8))
        #expect(record.group_id == id && record.revision == 7)
        #expect(record.theme.appearance == .classic)
        #expect(abs(WhisperWaveBackgroundRenderer.linearKeyComponent(0.5) - 0.21404114) < 0.00001)
    }

    @Test func suggestionsReplaceOnlyAnOpenHandle() {
        #expect(WhisperMentionToken.trailing(in: "hello @sa") == "sa")
        #expect(WhisperMentionToken.trailing(in: "@")=="")
        #expect(WhisperMentionToken.trailing(in: "mail@example.com") == nil)
        #expect(WhisperMentionToken.trailing(in: "@sa finished") == nil)
        #expect(WhisperMentionToken.replacingTrailing(in: "@first hi @sa", username: "saint") == "@first hi @saint ")
    }
}
