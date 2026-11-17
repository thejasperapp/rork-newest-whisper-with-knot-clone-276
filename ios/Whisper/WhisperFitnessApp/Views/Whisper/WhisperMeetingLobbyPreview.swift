import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Live self-view for the meeting lobby — runs its own lightweight
/// AVCaptureSession (front camera preferred, external webcam supported for
/// the cloud simulator) and pipes every frame through the SAME effect
/// settings as the in-call pipeline (`WhisperVideoEffects.shared`), so
/// picking Blur or a backdrop in the lobby previews instantly.
///
/// The session is preview-only: `stop()` is synchronous so `join()` can
/// release the camera before WebRTC's capturer claims it. It never touches
/// the RTC stack or the joining protocol.
@MainActor
@Observable
final class WhisperLobbyCameraSession {
    static let shared = WhisperLobbyCameraSession()

    enum Status: Equatable {
        case idle
        case starting
        case running
        case denied
        case unavailable
    }

    private(set) var status: Status = .idle
    private(set) var frame: CGImage?
    /// Self-previews mirror like a mirror for every self-facing camera
    /// (front AND external webcams) — only the back camera stays unmirrored.
    private(set) var shouldMirror: Bool = true

    private let engine = WhisperLobbyCaptureEngine()
    private var generation: UUID = UUID()

    private init() {}

    /// Starts (or restarts) the preview. Requests camera permission when
    /// it hasn't been decided yet.
    func start() {
        guard status != .running && status != .starting else { return }
        status = .starting
        let token = UUID(); generation = token
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginCapture(token: token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    guard self.generation == token, self.status == .starting else { return }
                    if granted {
                        self.beginCapture(token: token)
                    } else {
                        self.status = .denied
                    }
                }
            }
        default:
            status = .denied
        }
    }

    private func beginCapture(token: UUID) {
        guard generation == token, status == .starting else { return }
        engine.start(
            onReady: { [weak self] mirror in
                Task { @MainActor in
                    guard let self, self.generation == token, self.status == .starting else { return }
                    self.shouldMirror = mirror
                    self.status = .running
                }
            },
            onFrame: { [weak self] image in
                Task { @MainActor in
                    guard let self, self.generation == token, self.status == .running || self.status == .starting else { return }
                    self.frame = image
                }
            },
            onUnavailable: { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.status = .unavailable
                }
            }
        )
    }

    /// Synchronously releases the camera. Safe to call repeatedly; MUST run
    /// before the RTC capturer starts so the device is free.
    func stop() {
        generation = UUID()
        engine.stopSync()
        frame = nil
        status = .idle
    }
}

/// Background capture + effect compositing worker for the lobby preview.
/// Runs entirely off the main thread with its own Vision request and
/// CIContext (the RTC pipeline isn't active while the lobby is showing).
nonisolated final class WhisperLobbyCaptureEngine: NSObject, @unchecked Sendable {
    private let queue = DispatchQueue(label: "whisper.lobby.preview", qos: .userInitiated)
    private let session = AVCaptureSession()
    private var configured = false
    /// Apple's per-device rotation authority — knows the exact upright angle
    /// for landscape-mounted built-in sensors vs external webcams.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var onFrame: (@Sendable (CGImage) -> Void)?
    private var isProcessing = false

    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let segmentation: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    func start(
        onReady: @escaping @Sendable (Bool) -> Void,
        onFrame: @escaping @Sendable (CGImage) -> Void,
        onUnavailable: @escaping @Sendable () -> Void
    ) {
        queue.async { [self] in
            self.onFrame = onFrame
            if !configured {
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInWideAngleCamera, .external],
                    mediaType: .video,
                    position: .unspecified
                )
                let front = discovery.devices.first { $0.position == .front }
                guard let device = front ?? discovery.devices.first,
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    onUnavailable()
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .hd1280x720
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    onUnavailable()
                    return
                }
                session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: queue)
                guard session.canAddOutput(output) else {
                    session.commitConfiguration()
                    onUnavailable()
                    return
                }
                session.addOutput(output)
                videoOutput = output
                if let connection = output.connection(with: .video) {
                    // Ask Apple's rotation coordinator for THIS device's
                    // upright preview angle: built-in iPhone sensors are
                    // mounted landscape (90° in portrait) while external
                    // webcams (the cloud simulator's injected camera) already
                    // deliver upright frames (0°). Fall back to that
                    // heuristic only if the coordinator's angle is
                    // unsupported on this connection.
                    let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
                    rotationCoordinator = coordinator
                    var angle = coordinator.videoRotationAngleForHorizonLevelPreview
                    if !connection.isVideoRotationAngleSupported(angle) {
                        angle = device.deviceType == .external ? 0 : 90
                    }
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                }
                session.commitConfiguration()
                configured = true
                // Mirror unless this is explicitly the BACK camera — external
                // webcams (cloud simulator) face the user just like the front
                // camera, so an unmirrored preview reads as a flipped face.
                onReady(device.position != .back)
            } else {
                // Session reuse across lobby visits: re-read the coordinator
                // in case the device orientation changed in between.
                if let connection = videoOutput?.connection(with: .video),
                   let coordinator = rotationCoordinator {
                    let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                }
                onReady(true)
            }
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    /// Blocks until the capture session has fully stopped — the camera is
    /// guaranteed free when this returns.
    func stopSync() {
        queue.sync { [self] in
            onFrame = nil
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    /// Applies the active Whisper video effect (none / blur / backdrop) to
    /// a lobby frame. Any failure falls back to the raw frame.
    private func composited(_ pixelBuffer: CVPixelBuffer) -> CIImage {
        let raw = CIImage(cvPixelBuffer: pixelBuffer)
        let mode = WhisperVideoEffects.shared.mode
        guard mode != .off else { return raw }
        let backdrop = WhisperVideoEffects.shared.currentBackdropImage
        if mode == .backdrop && backdrop == nil { return raw }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        guard (try? handler.perform([segmentation])) != nil,
              let maskBuffer = segmentation.results?.first?.pixelBuffer else {
            return raw
        }
        var mask = CIImage(cvPixelBuffer: maskBuffer)
        let sx = raw.extent.width / mask.extent.width
        let sy = raw.extent.height / mask.extent.height
        mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        let background: CIImage
        switch mode {
        case .blur:
            background = raw
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 16)
                .cropped(to: raw.extent)
        case .backdrop:
            guard let backdrop else { return raw }
            let scale = max(
                raw.extent.width / backdrop.extent.width,
                raw.extent.height / backdrop.extent.height
            )
            var fitted = backdrop.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            fitted = fitted.transformed(by: CGAffineTransform(
                translationX: raw.extent.midX - fitted.extent.midX,
                y: raw.extent.midY - fitted.extent.midY
            ))
            background = fitted.cropped(to: raw.extent)
        case .off:
            return raw
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = raw
        blend.backgroundImage = background
        blend.maskImage = mask
        return blend.outputImage ?? raw
    }
}

extension WhisperLobbyCaptureEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isProcessing,
              let onFrame,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessing = true
        defer { isProcessing = false }
        let image = composited(pixelBuffer)
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return }
        onFrame(cg)
    }
}

/// SwiftUI face of the lobby preview — fills its container, mirrored for
/// self-facing cameras so it feels like a mirror.
struct WhisperLobbyCameraPreview: View {
    let session: WhisperLobbyCameraSession

    var body: some View {
        Color(white: 0.07)
            .overlay {
                if let frame = session.frame {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(x: session.shouldMirror ? -1 : 1, y: 1)
                        .allowsHitTesting(false)
                } else {
                    ProgressView()
                        .tint(.white.opacity(0.5))
                }
            }
            .clipped()
            .animation(.easeIn(duration: 0.18), value: session.frame == nil)
    }
}
