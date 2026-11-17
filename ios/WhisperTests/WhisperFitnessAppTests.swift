import Testing
import Foundation
import AVFoundation
import CoreImage
@testable import Whisper

struct WhisperWaveStudioTests {
    @Test func legacyClipRemainsReadable() throws {
        let original = WhisperWaveClip(url: URL(fileURLWithPath: "/tmp/source.mp4"), duration: 12)
        let data = try JSONEncoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "face"); object.removeValue(forKey: "background")
        let restored = try JSONDecoder().decode(WhisperWaveClip.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored == original)
        #expect(restored.background == nil)
    }

    @Test func subjectSettingsRoundTrip() throws {
        var clip = WhisperWaveClip(url: URL(fileURLWithPath: "/tmp/source.mp4"), duration: 4)
        clip.face = .init(kind: .bigEyes, amount: 0.7, smoothing: 0.3)
        clip.background = .init(url: URL(fileURLWithPath: "/tmp/background.mp4"), media: .video, removal: .chroma, subjectScale: 0.7, subjectX: 0.2)
        let restored = try JSONDecoder().decode(WhisperWaveClip.self, from: JSONEncoder().encode(clip))
        #expect(restored == clip)
    }

    @Test func backgroundRetainsShortTail() throws {
        let available = CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600))
        let output = CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600))
        let segments = WhisperWaveBackgroundLoop.segments(available: available, offset: 2.95, output: output)
        let first = try #require(segments.first)
        #expect(abs(first.source.start.seconds - 2.95) < 0.0001)
        #expect(abs(first.source.duration.seconds - 0.05) < 0.0001)
        #expect(segments.count == 2)
    }

    @Test func backgroundLoopsHaveNoRoundingGaps() throws {
        let available = CMTimeRange(start: CMTime(value: 7, timescale: 30_000), duration: CMTime(value: 10_001, timescale: 30_000))
        let output = CMTimeRange(start: CMTime(value: 601, timescale: 600), duration: CMTime(value: 360, timescale: 1))
        let segments = WhisperWaveBackgroundLoop.segments(available: available, offset: 0.321, output: output)
        var next = output.start
        for segment in segments {
            #expect(segment.destination == next)
            #expect(segment.source.start >= available.start)
            #expect(segment.source.end <= available.end)
            next = CMTimeAdd(segment.destination, segment.source.duration)
        }
        #expect(next == output.end)
    }

    @Test func chromaKeyRemovesGreenButKeepsForeground() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let green = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: extent)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 20, y: 20, width: 24, height: 24))
        let input = red.composited(over: green)
        let settings = WhisperWaveBackground(url: URL(fileURLWithPath: "/unused.png"), media: .photo, removal: .chroma, feather: 0, spill: 0)
        let cubes = WhisperWaveBackgroundRenderer.cubes(settings)
        let subject = WhisperWaveSubjectFrame(trackID: 1, range: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)), face: nil, background: settings, photo: nil, backgroundTrackID: nil, backgroundTransform: .identity, keyCube: cubes.mask, spillCube: cubes.spill)
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: extent)
        let result = try WhisperWaveBackgroundRenderer.render(input, subject: subject, background: blue, quality: .final)
        let corner = pixel(result, x: 5, y: 5)
        let center = pixel(result, x: 32, y: 32)
        #expect(corner[2] > 240 && corner[1] < 10)
        #expect(center[0] > 240 && center[2] < 10)
        #expect(center[3] == 255 && corner[3] == 255)
    }

    @Test func missingBackgroundNeverReturnsOriginalRoom() throws {
        let settings = WhisperWaveBackground(url: URL(fileURLWithPath: "/missing.png"), media: .photo)
        let subject = WhisperWaveSubjectFrame(trackID: 1, range: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)), face: nil, background: settings, photo: nil, backgroundTrackID: nil, backgroundTransform: .identity, keyCube: nil, spillCube: nil)
        let input = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        #expect(throws: (any Error).self) { try WhisperWaveBackgroundRenderer.render(input, subject: subject, background: nil, quality: .final) }
    }

    @Test func greenScreenCompositionAndExportUseMovingBackground() async throws {
        let source = try await video(colors: [CIColor(red: 0, green: 1, blue: 0)], framesPerColor: 30)
        let background = try await video(colors: [CIColor(red: 1, green: 0, blue: 0), CIColor(red: 0, green: 0, blue: 1)], framesPerColor: 6)
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: background) }
        var clip = WhisperWaveClip(url: source, duration: 1)
        clip.background = .init(url: background, media: .video, removal: .chroma, feather: 0, spill: 0)
        let built = try #require(await WhisperWaveClipStudio.makeComposition([clip], muteOriginal: true))
        let generator = AVAssetImageGenerator(asset: built.asset)
        generator.videoComposition = built.video
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let first = try await generator.image(at: CMTime(value: 3, timescale: 30)).image
        let second = try await generator.image(at: CMTime(value: 9, timescale: 30)).image
        #expect(pixel(CIImage(cgImage: first), x: 100, y: 100)[0] > 200)
        #expect(pixel(CIImage(cgImage: second), x: 100, y: 100)[2] > 200)
        let encoded = try await WhisperWaveBudgetEncoder().encode(asset: built.asset, video: built.video, audio: built.audio, progress: { _, _ in })
        defer { try? FileManager.default.removeItem(at: encoded) }
        let asset = AVURLAsset(url: encoded)
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 1) < 0.1)
        let final = AVAssetImageGenerator(asset: asset)
        final.requestedTimeToleranceBefore = .zero; final.requestedTimeToleranceAfter = .zero
        let last = try await final.image(at: CMTime(value: 27, timescale: 30)).image
        #expect(pixel(CIImage(cgImage: last), x: 100, y: 100)[0] > 200)
    }

    @Test func liveVideoLoopsAndSeeksOnTheBackgroundClock() async throws {
        let url = try await video(colors: [CIColor(red: 1, green: 0, blue: 0), CIColor(red: 0, green: 0, blue: 1)], framesPerColor: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try await WhisperWaveLiveVideoBackground.prepare(url)
        for time in [0.1, 0.3, 0.5, 0.7, 0.1] {
            let frame = try decoder.frame(seconds: time)
            #expect(frame.extent.width == 72 && frame.extent.height == 128)
            let color = pixel(frame, x: 30, y: 40)
            let expectsRed = time == 0.1 || time == 0.5
            #expect(color[expectsRed ? 0 : 2] > 200)
        }
    }

    @Test func faceEffectsDoNotRotateAnUprightCameraFrame() throws {
        let extent = CGRect(x: 0, y: 0, width: 72, height: 128)
        let bottom = CIImage(color: .blue).cropped(to: extent)
        let top = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 64, width: 72, height: 64)).composited(over: bottom)
        let fitted = WhisperWaveLiveFrameRenderer.fitCamera(top, canvas: extent)
        for kind in WhisperWaveFaceSetting.Kind.allCases {
            let rendered = try WhisperWaveFaceRenderer.render(fitted, setting: .init(kind: kind, amount: 0.35, smoothing: 0.3), observations: [])
            #expect(rendered.extent == extent)
            #expect(pixel(rendered, x: 20, y: 100)[0] > 240)
            #expect(pixel(rendered, x: 20, y: 20)[2] > 240)
        }
    }

    @Test func matchingBackdropCannotPanOutsideItsEdges() {
        let canvas = CGRect(x: 0, y: 0, width: 72, height: 128)
        let image = CIImage(color: .red).cropped(to: canvas)
        let settings = WhisperWaveBackground(url: URL(fileURLWithPath: "/test.jpg"), media: .photo, x: 1, y: -1)
        let fitted = WhisperWaveBackgroundRenderer.fitPhoto(image, settings: settings, canvas: canvas)
        #expect(pixel(fitted, x: 2, y: 2)[0] > 240)
        #expect(pixel(fitted, x: 70, y: 125)[0] > 240)
    }

    @Test func modalReadScopeSeparatesDirectAndGroupMessages() {
        let me = UUID().uuidString.lowercased(), sender = UUID().uuidString.lowercased()
        let group = UUID(), otherGroup = UUID()
        let directID = UUID().uuidString, groupID = UUID().uuidString
        let rows = [
            WhisperMessageRow(id: directID, from_user_id: sender, from_username: "friend", to_user_id: me, to_username: "me", body: "::whisper-program-v1::{\"name\":\"Plan\"}", created_at: "2026-09-16T00:00:00Z"),
            WhisperMessageRow(id: groupID, from_user_id: sender, from_username: "friend", to_user_id: me, to_username: "me", body: "::wg-v1::\(group)::Friends::card payload", created_at: "2026-09-16T00:00:01Z"),
            WhisperMessageRow(id: UUID().uuidString, from_user_id: sender, from_username: "friend", to_user_id: me, to_username: "me", body: "::wg-v1::\(otherGroup)::Other::text", created_at: "2026-09-16T00:00:02Z"),
            WhisperMessageRow(id: UUID().uuidString, from_user_id: me, from_username: "me", to_user_id: sender, to_username: "friend", body: "outgoing", created_at: "2026-09-16T00:00:03Z")
        ]
        #expect(WhisperMessageReadScope.unreadIDs(rows: rows, recipient: me, sender: sender) == [directID])
        #expect(WhisperMessageReadScope.unreadIDs(rows: rows, recipient: me, groupID: group) == [groupID])
        var read = rows[0]; read.read_at = "2026-09-16T00:01:00Z"
        #expect(WhisperMessageReadScope.unreadIDs(rows: [read], recipient: me).isEmpty)
        #expect(WhisperMessageReadScope.unreadIDs(rows: rows, recipient: UUID().uuidString).isEmpty)
    }

    @Test func oldGroupRegistryRowsDecodeWithoutAPicture() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","owner_id":"00000000-0000-0000-0000-000000000002","name":"Friends","member_ids":[],"member_usernames":[],"created_at":"2026-09-16T00:00:00Z"}
        """
        let row = try JSONDecoder().decode(WhisperGroupRegistryRow.self, from: Data(json.utf8))
        #expect(row.avatar_path == nil)
        #expect(row.name == "Friends")
    }

    @Test func rawCameraPixelsNormalizeBeforePortraitCropping() {
        let canvas = CGRect(x: 0, y: 0, width: 72, height: 128)
        let base = CIImage(color: .blue).cropped(to: canvas)
        let marker = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 64, width: 36, height: 64)).composited(over: base)
        let sideways = marker.oriented(forExifOrientation: 8)
        let upright = WhisperCameraFrameOrientation(clockwiseDegrees: 90, mirrored: false).normalize(sideways)
        #expect(upright.extent == canvas)
        #expect(pixel(upright, x: 12, y: 100)[0] > 240)
        #expect(pixel(upright, x: 60, y: 100)[2] > 240)
        let selfie = WhisperCameraFrameOrientation(clockwiseDegrees: 90, mirrored: true).normalize(sideways)
        #expect(pixel(selfie, x: 60, y: 100)[0] > 240)
        #expect(pixel(selfie, x: 12, y: 100)[2] > 240)
        #expect(pixel(selfie, x: 60, y: 20)[2] > 240)
    }

    @Test func uprightExternalLandscapeFeedDoesNotGetQuarterTurned() {
        let canvas = CGRect(x: 0, y: 0, width: 128, height: 72)
        let base = CIImage(color: .blue).cropped(to: canvas)
        let top = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 36, width: 128, height: 36)).composited(over: base)
        let normalized = WhisperCameraFrameOrientation(clockwiseDegrees: 0, mirrored: false).normalize(top)
        #expect(normalized.extent == canvas)
        #expect(pixel(normalized, x: 64, y: 60)[0] > 240)
        #expect(pixel(normalized, x: 64, y: 12)[2] > 240)
        #expect(WhisperCameraFrameOrientation.quarterTurn(-90) == 270)
        #expect(WhisperCameraFrameOrientation.quarterTurn(450) == 90)
    }

    @Test func recordedCameraEffectSurvivesDraftAndComposition() async throws {
        let source = try await video(colors: [.red], framesPerColor: 15)
        defer { try? FileManager.default.removeItem(at: source) }
        var clip = WhisperWaveClip(url: source, duration: 0.5)
        clip.cameraEffect = .mono
        let restored = try JSONDecoder().decode(WhisperWaveClip.self, from: JSONEncoder().encode(clip))
        #expect(restored.cameraEffect == .mono)
        let built = try #require(await WhisperWaveClipStudio.makeComposition([restored], muteOriginal: true))
        let generator = AVAssetImageGenerator(asset: built.asset)
        generator.videoComposition = built.video
        let frame = try await generator.image(at: CMTime(value: 3, timescale: 30)).image
        let color = pixel(CIImage(cgImage: frame), x: 400, y: 600)
        #expect(abs(Int(color[0]) - Int(color[1])) < 3)
        #expect(abs(Int(color[1]) - Int(color[2])) < 3)
    }

    @Test func storyEffectBakeProducesMatchingPlayableVideoAndPoster() async throws {
        let source = try await video(colors: [.red], framesPerColor: 9)
        defer { try? FileManager.default.removeItem(at: source) }
        let output = try await WhisperStoryCaptureEffects(effect: .mono).video(source)
        defer { try? FileManager.default.removeItem(at: output) }
        let asset = AVURLAsset(url: output)
        #expect(try await asset.load(.duration).seconds > 0.2)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let frame = try await generator.image(at: CMTime(value: 3, timescale: 30)).image
        let color = pixel(CIImage(cgImage: frame), x: 400, y: 600)
        #expect(abs(Int(color[0]) - Int(color[1])) < 5)
        #expect(abs(Int(color[1]) - Int(color[2])) < 5)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    private func pixel(_ image: CIImage, x: CGFloat, y: CGFloat) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.cacheIntermediates: false])
        context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return bytes
    }

    private func video(colors: [CIColor], framesPerColor: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wave-test-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 72, AVVideoHeightKey: 128])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 72, kCVPixelBufferHeightKey as String: 128])
        writer.add(input)
        try #require(writer.startWriting())
        defer { if writer.status == .writing { writer.cancelWriting() } }
        writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        for frame in 0..<(colors.count * framesPerColor) {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try #require(writer.status == .writing && Date() < deadline, "Synthetic writer stopped or timed out")
                try await Task.sleep(for: .milliseconds(3))
            }
            var buffer: CVPixelBuffer?
            let pool = try #require(adaptor.pixelBufferPool)
            #expect(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess)
            let pixelBuffer = try #require(buffer)
            context.render(CIImage(color: colors[frame / framesPerColor]).cropped(to: CGRect(x: 0, y: 0, width: 72, height: 128)), to: pixelBuffer)
            #expect(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: Int64(colors.count * framesPerColor), timescale: 30))
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }
}
