import AVFoundation
import CoreImage
import Foundation
import Vision

/// One upright viewfinder for every look. The raw movie remains private; settings render once at export.
nonisolated final class WhisperWaveLiveFrameRenderer: @unchecked Sendable {
    struct Configuration: Equatable, Sendable {
        var face: WhisperWaveFaceSetting = .init()
        var background: WhisperWaveBackground?
        var filter: SnapFilter = .none
        var speed: Double = 1
        var takeID: UUID?
        var cameraEffect: WhisperWaveCameraEffect = .none
        var catalogID: UUID?

        func hasSameRendering(as other: Configuration) -> Bool {
            var left = self; var right = other
            left.catalogID = nil; right.catalogID = nil
            return left == right
        }
    }
    private let lock = NSLock()
    private var config = Configuration()
    private var photo: CIImage?
    private var video: WhisperWaveLiveVideoBackground?
    private var cubes: (mask: Data, spill: Data)?
    private var preparedURL: URL?
    private var generation = UUID()
    private var deliveryPending = false
    private var isActive = true
    private let context = CIContext(options: [.cacheIntermediates: false])
    // These clocks belong exclusively to the capture queue.
    private var clockID: UUID?
    private var clockOrigin: Double?
    private var cadence = WhisperCameraFrameCadence()
    private let faceRequest = VNDetectFaceLandmarksRequest()
    private var lastCatalogID: UUID?
    private let poseTracker = WhisperFacePoseTracker()
    private var sourceGeneration: UUID?
    private var segmentationRequest = VNGeneratePersonSegmentationRequest()
    private var cubeSettings: WhisperWaveBackground?
    private var cachedCubes: (mask: Data, spill: Data)?

    func configure(_ next: Configuration, photo: CIImage?, video: WhisperWaveLiveVideoBackground?, preparedURL: URL?) {
        lock.lock(); defer { lock.unlock() }
        // A completed frame must match the selected recipe before capture is
        // declared ready. Catalog-only changes do not invalidate camera work.
        if !config.hasSameRendering(as: next) || self.preparedURL != preparedURL || self.photo !== photo || self.video !== video { generation = UUID() }
        config = next; self.photo = photo; self.video = video; self.preparedURL = preparedURL
    }

    func invalidate() { lock.lock(); isActive = false; generation = UUID(); lock.unlock() }

    func render(_ pixels: CVPixelBuffer, at time: CMTime, orientation: WhisperCameraFrameOrientation, sourceEpoch: UUID? = nil, recordingOrigin: CMTime? = nil, isSourceCurrent: @escaping @Sendable () -> Bool = { true }, deliver: @escaping @MainActor @Sendable (CGImage?, String?, CGImage?, Double) -> Void) {
        let now = time.seconds
        lock.lock()
        if deliveryPending || !isActive { lock.unlock(); return }
        guard cadence.admits(now) else { lock.unlock(); return }
        deliveryPending = true
        let settings = config; let photo = self.photo; let video = self.video
        let token = generation; let readyURL = preparedURL
        let catalogAcknowledged = lastCatalogID
        lock.unlock()
        if sourceGeneration != sourceEpoch { poseTracker.reset(); segmentationRequest = VNGeneratePersonSegmentationRequest(); sourceGeneration = sourceEpoch }
        if let background = settings.background, background.removal == .chroma {
            if cubeSettings?.keyRed != background.keyRed || cubeSettings?.keyGreen != background.keyGreen || cubeSettings?.keyBlue != background.keyBlue || cubeSettings?.tolerance != background.tolerance || cubeSettings?.feather != background.feather || cubeSettings?.spill != background.spill || cachedCubes == nil {
                cachedCubes = WhisperWaveBackgroundRenderer.cubes(background)
                cubeSettings = background
            }
        }
        let cubes = cachedCubes
        if clockID != settings.takeID { clockID = settings.takeID; clockOrigin = now }
        if clockOrigin == nil { clockOrigin = now }
        // iOS 18.2+ supplies the first movie sample's PTS on the capture clock.
        // iOS 18.0/18.1 retain a best-effort first-preview-frame fallback.
        let origin = settings.takeID == nil ? clockOrigin : (recordingOrigin?.seconds ?? clockOrigin)
        let elapsed = max(0, now - (origin ?? now)) / (settings.takeID == nil ? 1 : max(0.1, settings.speed))
        var result: CGImage?
        var issue: String?
        var catalog: CGImage?
        autoreleasepool {
            do {
                let source = orientation.normalize(CIImage(cvPixelBuffer: pixels))
                let canvas = CGRect(x: 0, y: 0, width: 540, height: 960)
                let image = Self.fitCamera(source, canvas: canvas)
                var backdrop: CIImage?
                if let background = settings.background {
                    guard readyURL == background.url else { throw CocoaError(.fileReadUnknown) }
                    let raw: CIImage
                    if background.media == .photo {
                        guard let photo else { throw CocoaError(.fileReadUnknown) }; raw = photo
                    } else {
                        guard let video else { throw CocoaError(.fileReadUnknown) }
                        raw = try video.frame(seconds: background.startTime + elapsed)
                    }
                    backdrop = WhisperWaveBackgroundRenderer.fitPhoto(raw, settings: background, canvas: canvas)
                }
                let faces = try settings.face.isActive ? WhisperWaveFaceRenderer.detect(image, request: faceRequest) : []
                let poses = poseTracker.update(WhisperARProcessor.shared.faceFrames(faces, extent: image.extent), time: now)
                let composite = try WhisperWaveBackgroundRenderer.render(image, face: settings.face, settings: settings.background, background: backdrop, keyCube: cubes?.mask, spillCube: cubes?.spill, quality: .preview, observations: faces, frames: poses, segmentationRequest: segmentationRequest, time: elapsed)
                let effected = try WhisperWaveCameraEffectRenderer.render(composite, effect: settings.cameraEffect, time: elapsed, quality: .preview)
                if let id = settings.catalogID, id != catalogAcknowledged {
                    // Thumbnails only see the protected composite, never a hidden original room.
                    let protected = try WhisperWaveBackgroundRenderer.render(image, face: .init(), settings: settings.background, background: backdrop, keyCube: cubes?.mask, spillCube: cubes?.spill, quality: .preview)
                    let seed = settings.cameraEffect == .cloneWall ? try WhisperWaveCameraEffectRenderer.render(protected, effect: .cloneWall, time: elapsed, quality: .preview) : protected
                    let small = seed.transformed(by: CGAffineTransform(scaleX: 0.3, y: 0.3))
                    catalog = context.createCGImage(small, from: small.extent)
                }
                let graded = WhisperWaveColorAdjustments().process(effected, filter: settings.filter)
                result = context.createCGImage(graded, from: canvas)
                if result == nil { issue = "Camera preview couldn't render. Try again." }
            } catch {
                poseTracker.reset()
                if (error as NSError).domain == "WhisperFace3D" {
                    issue = "3D effect couldn't render. Choose another effect or retry before capturing."
                } else {
                    issue = settings.background == nil ? "Face effect couldn't render. Try None or retry." : "Background isn't ready. Replace it or retry before recording."
                }
            }
        }
        let frame = result; let message = issue; let snapshot = catalog
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sourceCurrent = isSourceCurrent()
            let current = self.finishDelivery(token, catalogID: snapshot == nil || !sourceCurrent ? nil : settings.catalogID)
            if current && sourceCurrent { deliver(frame, message, snapshot, elapsed) }
        }
    }

    private func finishDelivery(_ token: UUID, catalogID: UUID?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        deliveryPending = false
        let current = isActive && generation == token
        if current, let catalogID { lastCatalogID = catalogID }
        return current
    }

    static func fitCamera(_ source: CIImage, canvas: CGRect) -> CIImage {
        let extent = source.extent
        let scale = max(canvas.width / extent.width, canvas.height / extent.height)
        return source.transformed(by: CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: canvas.midX, y: canvas.midY))).cropped(to: canvas)
    }
}
