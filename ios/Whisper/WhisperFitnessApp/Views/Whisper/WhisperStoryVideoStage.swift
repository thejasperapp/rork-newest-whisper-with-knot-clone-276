import SwiftUI
import AVFoundation
import AVKit
import CoreImage
import UIKit

/// Looping video layer for the story editor's 9:16 stage. Aspect-FIT like
/// the still-photo layer so a portrait clip fills the stage exactly and a
/// landscape clip letterboxes over the blurred backdrop.
struct WhisperStoryVideoStage: View {
    let url: URL
    var muted: Bool = true
    @State private var player: AVQueuePlayer = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?

    var body: some View {
        WhisperStoryStagePlayerLayer(player: player, gravity: .resizeAspect)
            .onAppear {
                if looper == nil {
                    let item = AVPlayerItem(url: url)
                    looper = AVPlayerLooper(player: player, templateItem: item)
                }
                player.isMuted = muted || WhisperCameraCallMonitor.shared.callOwnsAudio
                player.play()
            }
            .onChange(of: muted) { _, m in player.isMuted = m || WhisperCameraCallMonitor.shared.callOwnsAudio }
            .onChange(of: WhisperCameraCallMonitor.shared.callOwnsAudio) { _, busy in player.isMuted = muted || busy }
            .onDisappear { player.pause() }
    }
}

struct WhisperStoryStagePlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.backgroundColor = .clear
        v.playerLayer.player = player
        v.playerLayer.videoGravity = gravity
        return v
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
        if uiView.playerLayer.videoGravity != gravity { uiView.playerLayer.videoGravity = gravity }
    }
}

/// Story-viewer playback for video stories: plays once from the top of the
/// story (the viewer's progress bar owns the clock), pauses with the hold
/// gesture, mutes when a music track rides the story, and reports the
/// clip's real duration so the segment lasts exactly as long as the video.
struct WhisperStoryViewerVideo: View {
    let url: URL
    var paused: Bool = false
    var muted: Bool = true
    var onDuration: (Double) -> Void = { _ in }
    var onProgress: (Double) -> Void = { _ in }
    var onReady: () -> Void = {}
    var onFailure: (() -> Void)? = nil
    var replayID: UUID? = nil
    @State private var retryID: UUID = UUID()
    @State private var failed: Bool = false
    @State private var player: AVPlayer = AVPlayer()
    @State private var ready: Bool = false
    @State private var hasEnded: Bool = false

    var body: some View {
        ZStack {
            Color.black
            WhisperStoryStagePlayerLayer(player: player, gravity: .resizeAspectFill)
                .opacity(ready ? 1 : 0)
            if failed, onFailure == nil {
                VStack(spacing: 12) {
                    Text("Couldn't play this video").font(.subheadline)
                    Button("Try again") { retryID = UUID() }.frame(minHeight: 44)
                }.foregroundStyle(.white)
            } else if !failed && !ready {
                ProgressView().tint(.white)
            }
        }
        .task(id: "\(url.absoluteString)|\(replayID?.uuidString ?? "")|\(retryID)") {
            ready = false; failed = false; hasEnded = false
            onProgress(0)
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 2
            player.replaceCurrentItem(with: item)
            player.actionAtItemEnd = .pause
            player.isMuted = muted || WhisperCameraCallMonitor.shared.callOwnsAudio
            if !WhisperCameraCallMonitor.shared.callOwnsAudio {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            }
            _ = await player.seek(to: .zero)
            guard !Task.isCancelled, player.currentItem === item else { return }
            if !paused { player.play() }
            while !Task.isCancelled, !hasEnded, player.currentItem === item {
                if item.status == .failed { failed = true; onFailure?(); return }
                let seconds = player.currentTime().seconds
                let total = item.duration.seconds
                if seconds.isFinite, seconds > 0 {
                    if !ready { ready = true; onReady() }
                    if total.isFinite, total > 0 {
                        onDuration(total)
                        onProgress(min(1, seconds / total))
                    }
                }
                do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { notification in
            guard let item = notification.object as? AVPlayerItem, player.currentItem === item else { return }
            hasEnded = true
            onProgress(1)
        }
        .onChange(of: paused) { _, p in
            if p { player.pause() } else { player.play() }
        }
        .onChange(of: muted) { _, m in player.isMuted = m || WhisperCameraCallMonitor.shared.callOwnsAudio }
        .onChange(of: WhisperCameraCallMonitor.shared.callOwnsAudio) { _, busy in player.isMuted = muted || busy }
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }
}

// MARK: - Poster frames

nonisolated enum WhisperStoryPoster {
    /// First frame of a clip as an upright UIImage — the story's poster.
    static func firstFrame(of url: URL, maxSize: CGSize = CGSize(width: 1080, height: 1920)) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = maxSize
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        do {
            let (cg, _) = try await gen.image(at: CMTime(seconds: 0.05, preferredTimescale: 600))
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }

    /// Duration in seconds (0 when unreadable).
    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let d = try? await asset.load(.duration) else { return 0 }
        let s = d.seconds
        return s.isFinite ? s : 0
    }
}

// MARK: - Wave → story background

/// Shared-post backdrops, prepared once off the UI thread at export resolution.
nonisolated enum WhisperWaveStoryBackground {
    static func gradient(from cover: UIImage?, size: CGSize = CGSize(width: 1080, height: 1920)) -> UIImage {
        let (top, bottom) = sample(cover)
        return render(top: top, bottom: bottom, size: size)
    }

    /// Instagram's ACTUAL shared-post backdrop: the post's own picture,
    /// scaled to fill the 1080×1920 canvas and blurred heavily with a soft
    /// darkening so the card and white chrome read on top. Falls back to the
    /// sampled gradient when there's no cover (text posts).
    static func blurred(from cover: UIImage?, size: CGSize = CGSize(width: 1080, height: 1920)) -> UIImage {
        guard let cover, cover.size.width > 0, cover.size.height > 0 else { return gradient(from: nil, size: size) }
        // UIKit drawing normalizes EXIF orientation and limits the working bitmap.
        let upright = filledPhoto(cover, size: size)
        guard let cg = upright.cgImage else { return gradient(from: nil, size: size) }
        let ci = CIImage(cgImage: cg)
        let extent = ci.extent
        guard extent.width > 2, extent.height > 2 else { return gradient(from: cover, size: size) }
        // Aspect-fill the canvas, then blur at a radius scaled to the canvas.
        let scale = max(size.width / extent.width, size.height / extent.height)
        let filled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let fx = (filled.extent.width - size.width) / 2
        let fy = (filled.extent.height - size.height) / 2
        let cropped = filled.cropped(to: CGRect(x: filled.extent.minX + fx, y: filled.extent.minY + fy, width: size.width, height: size.height))
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return gradient(from: cover, size: size) }
        blur.setValue(cropped.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(size.width * 0.09, forKey: kCIInputRadiusKey)
        guard let blurredOut = blur.outputImage?.cropped(to: cropped.extent) else { return gradient(from: cover, size: size) }
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        guard let outCG = ctx.createCGImage(blurredOut.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.9]), from: blurredOut.extent) else { return gradient(from: cover, size: size) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { rctx in
            UIImage(cgImage: outCG).draw(in: CGRect(origin: .zero, size: size))
            // RendererContext.fill defaults to copy; use normal compositing so
            // the tint darkens the photo rather than replacing it with black.
            rctx.cgContext.setBlendMode(.normal)
            rctx.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.28).cgColor)
            rctx.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func filledPhoto(_ image: UIImage, size: CGSize = CGSize(width: 1080, height: 1920)) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill(); context.fill(CGRect(origin: .zero, size: size))
            guard image.size.width > 0, image.size.height > 0 else { return }
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height))
        }
    }

    /// Average color of the top and bottom halves via CIAreaAverage — a
    /// single 1×1 readback each, so this stays cheap on any photo size.
    static func sample(_ image: UIImage?) -> (UIColor, UIColor) {
        let fallback = (UIColor(red: 0.16, green: 0.12, blue: 0.24, alpha: 1), UIColor(red: 0.05, green: 0.04, blue: 0.08, alpha: 1))
        guard let image, let cg = image.cgImage else { return fallback }
        let ci = CIImage(cgImage: cg)
        let extent = ci.extent
        guard extent.width > 2, extent.height > 2 else { return fallback }
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        func average(_ rect: CGRect) -> UIColor? {
            guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
            filter.setValue(ci, forKey: kCIInputImageKey)
            filter.setValue(CIVector(cgRect: rect), forKey: kCIInputExtentKey)
            guard let out = filter.outputImage else { return nil }
            var px = [UInt8](repeating: 0, count: 4)
            ctx.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            return UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        }
        // CIImage origin is bottom-left: the visual TOP half is the upper rect.
        let topRect = CGRect(x: extent.minX, y: extent.midY, width: extent.width, height: extent.height / 2)
        let bottomRect = CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: extent.height / 2)
        let top = deepen(average(topRect) ?? fallback.0, by: 0.72)
        let bottom = deepen(average(bottomRect) ?? fallback.1, by: 0.42)
        return (top, bottom)
    }

    /// Pull a sampled color toward a rich, dark version of itself so white
    /// chrome and the card always read on top (IG's gradients are moody).
    private static func deepen(_ c: UIColor, by factor: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard c.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return c }
        return UIColor(hue: h, saturation: min(1, max(0.35, s * 1.25)), brightness: min(0.75, max(0.12, b * factor)), alpha: 1)
    }

    static func render(top: UIColor, bottom: UIColor, size: CGSize = CGSize(width: 1080, height: 1920)) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            } else {
                top.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
        }
    }
}

// MARK: - Wave sticker factory

extension WhisperStorySticker {
    /// The "Add wave to your story" card, centered on the canvas.
    nonisolated static func wave(post: WhisperPost) -> WhisperStorySticker {
        var s = WhisperStorySticker(kind: .wave)
        s.x = 0.5
        s.y = 0.47
        s.scale = 1.0
        s.postID = post.id.uuidString.lowercased()
        s.label = post.username
        let cap = post.displayCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        s.text = cap.isEmpty ? nil : String(cap.prefix(60))
        let video = post.mediaURLs.first(where: { WhisperVideo.isVideo($0) })
        s.videoURL = video?.absoluteString
        // Cover: the first non-video media if any; video-only waves show the
        // muted loop in the viewer and a play glyph on the editor canvas.
        let still = post.mediaURLs.first(where: { !WhisperVideo.isVideo($0) })
        s.imageURL = still?.absoluteString
        return s
    }

    /// The "Add post to your story" card — a grid/photo post as a white
    /// post card centered on the canvas. Waves route to `wave(post:)`.
    nonisolated static func post(post: WhisperPost) -> WhisperStorySticker {
        var s = WhisperStorySticker(kind: .post)
        s.x = 0.5
        s.y = 0.47
        s.scale = 1.0
        s.postID = post.id.uuidString.lowercased()
        s.label = post.username
        let cap = post.displayCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        s.text = cap.isEmpty ? nil : String(cap.prefix(90))
        let still = post.mediaURLs.first(where: { !WhisperVideo.isVideo($0) })
        s.imageURL = still?.absoluteString
        return s
    }

    /// The right story card for any post — waves get the tall watch card,
    /// everything else the white post card.
    nonisolated static func card(for post: WhisperPost) -> WhisperStorySticker {
        let hasVideo = post.mediaURLs.contains(where: { WhisperVideo.isVideo($0) })
        return (post.isReel || hasVideo) ? wave(post: post) : Self.post(post: post)
    }
}
