import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import UIKit
import Vision
import WebRTC

/// Which effect the local camera pipeline applies before frames are encoded.
nonisolated enum WhisperVideoEffectMode: String, CaseIterable, Sendable {
    case off
    case blur
    case backdrop
}

/// Real-time virtual-background engine for every Whisper video surface
/// (meetings, video calls, lives). Sits between `RTCCameraVideoCapturer`
/// and the `RTCVideoSource` as a capture delegate proxy:
///
///   camera → WhisperVideoEffects (person segmentation + compositing) → source
///
/// - `.off`      — frames pass through untouched (zero overhead).
/// - `.blur`     — Google Meet-style background blur behind the person.
/// - `.backdrop` — a chosen or AI-generated image replaces the background.
///
/// Runs entirely on the WebRTC capture thread with Vision person
/// segmentation; any failure falls back to the raw frame so video never
/// freezes because of an effect.
nonisolated final class WhisperVideoEffects: NSObject, @unchecked Sendable {
    static let shared = WhisperVideoEffects()

    private let lock = NSLock()
    private var _mode: WhisperVideoEffectMode = .off
    private var backdropImage: CIImage?
    /// Temporary backdrop override (shared room scenes) that outranks the
    /// user's own effect WITHOUT touching their persisted choice.
    private var overrideBackdrop: CIImage?
    private weak var output: RTCVideoSource?
    /// Aspect-fill-fitted backdrop cached per frame size + rotation.
    private var fittedBackdrop: CIImage?
    private var fittedSize: CGSize = .zero
    private var fittedRotation: RTCVideoRotation = ._0

    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let segmentation: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    private var pool: CVPixelBufferPool?
    private var poolWidth: Int = 0
    private var poolHeight: Int = 0

    private static let modeKey = "whisper.videofx.mode"
    private static let imageKey = "whisper.videofx.imagePath"

    private override init() {
        super.init()
        restorePersisted()
    }

    // MARK: - Public control (thread-safe)

    var mode: WhisperVideoEffectMode {
        lock.withLock { _mode }
    }

    var hasBackdropImage: Bool {
        lock.withLock { backdropImage != nil }
    }

    /// Decoded backdrop image for preview pipelines (lobby camera preview
    /// composites with its own segmentation request).
    var currentBackdropImage: CIImage? {
        lock.withLock { backdropImage }
    }

    /// Path of the persisted backdrop image, if one is selected.
    var backdropPath: String? {
        UserDefaults.standard.string(forKey: Self.imageKey)
    }

    /// Point the proxy at the live video source. Called by
    /// `WhisperLiveRTCService` whenever a local media stream is created.
    func attach(to source: RTCVideoSource?) {
        lock.withLock { output = source }
    }

    func setMode(_ mode: WhisperVideoEffectMode) {
        lock.withLock {
            _mode = mode
            fittedBackdrop = nil
        }
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
    }

    /// Select a backdrop image (switches mode to `.backdrop`). Pass a file
    /// path to persist the selection across launches.
    func setBackdrop(_ image: UIImage?, persistPath: String?) {
        let ci: CIImage? = image.flatMap { img in
            if let cg = img.cgImage { return CIImage(cgImage: cg) }
            return CIImage(image: img)
        }
        lock.withLock {
            backdropImage = ci
            fittedBackdrop = nil
            if ci != nil { _mode = .backdrop }
        }
        if ci != nil {
            UserDefaults.standard.set(WhisperVideoEffectMode.backdrop.rawValue, forKey: Self.modeKey)
            if let persistPath {
                UserDefaults.standard.set(persistPath, forKey: Self.imageKey)
            }
        }
    }

    /// Applies (or clears with `nil`) a temporary backdrop that wins over the
    /// user's own effect while set. Never persisted — ending the show returns
    /// their saved choice untouched.
    func setOverrideBackdrop(_ image: UIImage?) {
        let ci: CIImage? = image.flatMap { img in
            if let cg = img.cgImage { return CIImage(cgImage: cg) }
            return CIImage(image: img)
        }
        lock.withLock {
            overrideBackdrop = ci
            fittedBackdrop = nil
        }
    }

    private func restorePersisted() {
        let stored = UserDefaults.standard.string(forKey: Self.modeKey)
        let restoredMode = stored.flatMap(WhisperVideoEffectMode.init(rawValue:)) ?? .off
        var image: CIImage?
        if restoredMode == .backdrop,
           let path = UserDefaults.standard.string(forKey: Self.imageKey),
           let ui = UIImage(contentsOfFile: path) {
            image = ui.cgImage.map(CIImage.init(cgImage:)) ?? CIImage(image: ui)
        }
        lock.withLock {
            backdropImage = image
            _mode = (restoredMode == .backdrop && image == nil) ? .off : restoredMode
        }
    }

    // MARK: - Saved backdrop storage

    /// Directory that holds generated / imported backdrop images.
    static func backgroundsDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("whisper-videofx", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Saved backdrop file paths, newest first.
    static func savedBackdropPaths() -> [String] {
        let dir = backgroundsDirectory()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files
            .filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
            .map(\.path)
    }

    /// Deletes a saved backdrop image. If it was the active backdrop the
    /// effect switches off so the pipeline never references a missing file.
    static func deleteBackdrop(atPath path: String) {
        try? FileManager.default.removeItem(atPath: path)
        guard UserDefaults.standard.string(forKey: imageKey) == path else { return }
        UserDefaults.standard.removeObject(forKey: imageKey)
        UserDefaults.standard.set(WhisperVideoEffectMode.off.rawValue, forKey: modeKey)
        shared.lock.withLock {
            shared.backdropImage = nil
            shared.fittedBackdrop = nil
            shared._mode = .off
        }
    }

    /// Downscales + persists an image, returning the saved file path.
    static func saveBackdrop(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1440
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let url = backgroundsDirectory().appendingPathComponent("bg-\(UUID().uuidString).jpg")
        do {
            try jpeg.write(to: url)
            return url.path
        } catch {
            print("[WhisperVideoEffects] save failed: \(error)")
            return nil
        }
    }

    // MARK: - Frame processing

    fileprivate func processIncoming(_ capturer: RTCVideoCapturer, frame: RTCVideoFrame) {
        let (target, storedMode, storedBackdrop, showBackdrop): (RTCVideoSource?, WhisperVideoEffectMode, CIImage?, CIImage?) = lock.withLock {
            (output, _mode, backdropImage, overrideBackdrop)
        }
        guard let target else { return }
        // A show-time override outranks the user's own effect while it lasts.
        let mode: WhisperVideoEffectMode = showBackdrop != nil ? .backdrop : storedMode
        let backdrop: CIImage? = showBackdrop ?? storedBackdrop
        guard mode != .off,
              let rtcBuffer = frame.buffer as? RTCCVPixelBuffer else {
            target.capturer(capturer, didCapture: frame)
            return
        }
        if mode == .backdrop && backdrop == nil {
            target.capturer(capturer, didCapture: frame)
            return
        }
        guard let processed = process(rtcBuffer.pixelBuffer, mode: mode, backdrop: backdrop, rotation: frame.rotation) else {
            target.capturer(capturer, didCapture: frame)
            return
        }
        let newFrame = RTCVideoFrame(
            buffer: RTCCVPixelBuffer(pixelBuffer: processed),
            rotation: frame.rotation,
            timeStampNs: frame.timeStampNs
        )
        target.capturer(capturer, didCapture: newFrame)
    }

    private func process(
        _ pixelBuffer: CVPixelBuffer,
        mode: WhisperVideoEffectMode,
        backdrop: CIImage?,
        rotation: RTCVideoRotation
    ) -> CVPixelBuffer? {
        // Orientation hint keeps segmentation quality high in portrait; the
        // resulting mask is rotated back into raw buffer space below.
        let orientation = Self.visionOrientation(for: rotation)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([segmentation])
        } catch {
            return nil
        }
        guard let maskBuffer = segmentation.results?.first?.pixelBuffer else { return nil }

        let fg = CIImage(cvPixelBuffer: pixelBuffer)
        var mask = CIImage(cvPixelBuffer: maskBuffer).oriented(Self.inverse(of: orientation))
        let sx = fg.extent.width / mask.extent.width
        let sy = fg.extent.height / mask.extent.height
        mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        let background: CIImage
        switch mode {
        case .blur:
            background = fg
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 16)
                .cropped(to: fg.extent)
        case .backdrop:
            guard let backdrop else { return nil }
            background = fitted(backdrop, to: fg.extent, rotation: rotation)
        case .off:
            return nil
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = fg
        blend.backgroundImage = background
        blend.maskImage = mask
        guard let outImage = blend.outputImage else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let outBuffer = dequeueBuffer(width: width, height: height) else { return nil }
        ciContext.render(
            outImage,
            to: outBuffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return outBuffer
    }

    /// Aspect-fills `image` into the frame, oriented for the user's CURRENT
    /// device orientation. The camera delivers landscape pixel buffers with a
    /// rotation tag the renderer applies at draw time — so the backdrop must
    /// be composed in DISPLAY space (portrait when the phone is upright) and
    /// then rotated back into raw buffer space. Compositing directly into the
    /// landscape buffer (the old behavior) made every backdrop render
    /// sideways/landscape for portrait users.
    private func fitted(_ image: CIImage, to extent: CGRect, rotation: RTCVideoRotation) -> CIImage {
        lock.lock()
        if let cached = fittedBackdrop, fittedSize == extent.size, fittedRotation == rotation {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // 1. Fit the backdrop upright, as the user will SEE it.
        let swapped = rotation == ._90 || rotation == ._270
        let displayRect = swapped
            ? CGRect(x: 0, y: 0, width: extent.height, height: extent.width)
            : CGRect(origin: .zero, size: extent.size)

        let scale = max(displayRect.width / image.extent.width, displayRect.height / image.extent.height)
        var out = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = displayRect.midX - out.extent.midX
        let dy = displayRect.midY - out.extent.midY
        out = out
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .cropped(to: displayRect)

        // 2. Rotate into raw buffer space so the renderer's rotation lands
        //    it upright again.
        let orientation = Self.visionOrientation(for: rotation)
        if orientation != .up {
            out = out.oriented(Self.inverse(of: orientation))
            out = out.transformed(by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY))
            out = out.cropped(to: CGRect(origin: .zero, size: extent.size))
        }

        lock.withLock {
            fittedBackdrop = out
            fittedSize = extent.size
            fittedRotation = rotation
        }
        return out
    }

    private func dequeueBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        lock.lock()
        if pool == nil || poolWidth != width || poolHeight != height {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            var newPool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &newPool)
            pool = newPool
            poolWidth = width
            poolHeight = height
        }
        let currentPool = pool
        lock.unlock()

        guard let currentPool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, currentPool, &buffer)
        return buffer
    }

    private static func visionOrientation(for rotation: RTCVideoRotation) -> CGImagePropertyOrientation {
        switch rotation {
        case ._0: return .up
        case ._90: return .right
        case ._180: return .down
        case ._270: return .left
        @unknown default: return .up
        }
    }

    private static func inverse(of orientation: CGImagePropertyOrientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .right: return .left
        case .left: return .right
        default: return orientation
        }
    }
}

// MARK: - RTCVideoCapturerDelegate proxy

extension WhisperVideoEffects: RTCVideoCapturerDelegate {
    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        processIncoming(capturer, frame: frame)
    }
}
