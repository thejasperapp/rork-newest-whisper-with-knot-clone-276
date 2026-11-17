import AVFoundation
import CoreImage
import Metal

/// One GPU-backed frame pipeline for transitions, framing, effects, grading and text.
nonisolated final class WhisperWaveVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "whisper.wave.frames", qos: .userInitiated)
    private let lock = NSLock()
    private var epoch: UInt64 = 0
    private var trackingEpoch: UInt64?
    private let faceTracking = WhisperWaveVideoFaceTracking()
    private let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        queue.async { [self] in faceTracking.reset() }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        lock.lock(); let token = epoch; lock.unlock()
        queue.async { [self] in
            lock.lock(); let cancelled = token != epoch; lock.unlock()
            if cancelled { request.finishCancelledRequest(); return }
            if trackingEpoch != token { faceTracking.reset(); trackingEpoch = token }
            autoreleasepool {
                do {
                    guard let instruction = request.videoCompositionInstruction as? WhisperWaveVideoInstruction,
                          let output = request.renderContext.newPixelBuffer() else { throw CocoaError(.coderInvalidValue) }
                    let image = try Self.frame(instruction, time: request.compositionTime, faceTracking: faceTracking) { request.sourceFrame(byTrackID: $0) }
                    let scale = CGAffineTransform(scaleX: CGFloat(CVPixelBufferGetWidth(output)) / instruction.canvas.width,
                                                  y: CGFloat(CVPixelBufferGetHeight(output)) / instruction.canvas.height)
                    context.render(image.transformed(by: scale), to: output)
                    lock.lock(); let isCurrent = epoch == token; lock.unlock()
                    if isCurrent { request.finish(withComposedVideoFrame: output) }
                    else { faceTracking.reset(); request.finishCancelledRequest() }
                } catch { faceTracking.reset(); request.finish(with: error) }
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() { lock.lock(); epoch &+= 1; lock.unlock() }

    static func frame(_ instruction: WhisperWaveVideoInstruction, time: CMTime, faceTracking: WhisperWaveVideoFaceTracking? = nil, source: (CMPersistentTrackID) -> CVPixelBuffer?) throws -> CIImage {
        faceTracking?.retain(Set(instruction.subjects.filter { CMTimeRangeContainsTime($0.range, time: time) }.map(\.trackingID)))
        let canvas = CGRect(origin: .zero, size: instruction.canvas)
        var result = CIImage(color: .black).cropped(to: canvas)
        for layer in instruction.base.layerInstructions.reversed() {
            var transform = CGAffineTransform.identity
            layer.getTransformRamp(for: time, start: &transform, end: nil, timeRange: nil)
            var start: Float = 1
            var end: Float = 1
            var range = CMTimeRange.invalid
            let hasOpacity = layer.getOpacityRamp(for: time, startOpacity: &start, endOpacity: &end, timeRange: &range)
            let progress = range.duration.seconds > 0 ? min(1, max(0, (time.seconds - range.start.seconds) / range.duration.seconds)) : 0
            let opacity = hasOpacity ? start + (end - start) * Float(progress) : 1
            guard opacity > 0 else { continue }
            guard let buffer = source(layer.trackID) else { throw CocoaError(.fileReadCorruptFile) }
            let raw = CIImage(cvPixelBuffer: buffer)
            // AV transforms use top-left coordinates; Core Image uses bottom-left.
            let flipSource = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: raw.extent.height)
            let flipCanvas = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvas.height)
            var image = raw.transformed(by: flipSource.concatenating(transform).concatenating(flipCanvas)).cropped(to: canvas)
            let subject = instruction.subjects.first { $0.trackID == layer.trackID && CMTimeRangeContainsTime($0.range, time: time) }
            let legacy = instruction.effect
            // Legacy global accessory IDs use the same 3D/cutout path as clip-local
            // recipes. An explicit clip setting, including None, keeps precedence.
            let inheritedFace = legacy.isFace ? WhisperWaveFaceSetting.Kind(rawValue: legacy.rawValue).map { WhisperWaveFaceSetting.current($0) } : nil
            let face = subject?.face ?? inheritedFace
            let effectTime = subject.map { time.seconds - $0.range.start.seconds + $0.effectTimeOffset } ?? time.seconds
            if legacy.isBackground, subject?.background == nil {
                image = try WhisperARProcessor.shared.render(image, effect: legacy, quality: instruction.quality == .preview ? .live : .export, time: effectTime)
            }
            if let subject {
                var background: CIImage?
                if let photo = subject.photo, let settings = subject.background {
                    background = WhisperWaveBackgroundRenderer.fitPhoto(photo, settings: settings, canvas: canvas)
                } else if let id = subject.backgroundTrackID {
                    guard let buffer = source(id) else { throw CocoaError(.fileReadCorruptFile) }
                    let rawBackground = CIImage(cvPixelBuffer: buffer)
                    let flipBackground = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rawBackground.extent.height)
                    background = rawBackground.transformed(by: flipBackground.concatenating(subject.backgroundTransform).concatenating(flipCanvas)).cropped(to: canvas).composited(over: CIImage(color: .black).cropped(to: canvas))
                }
                if face?.kind.accessory != nil, let faceTracking {
                    let tracked = try faceTracking.analyze(image, id: subject.trackingID, time: time)
                    image = try WhisperWaveBackgroundRenderer.render(image, face: face, settings: subject.background, background: background, keyCube: subject.keyCube, spillCube: subject.spillCube, quality: instruction.quality, observations: tracked.observations, frames: tracked.frames, time: effectTime)
                } else {
                    image = try WhisperWaveBackgroundRenderer.render(image, face: face, settings: subject.background, background: background, keyCube: subject.keyCube, spillCube: subject.spillCube, quality: instruction.quality, time: effectTime)
                }
                if let effect = subject.cameraEffect {
                    image = try WhisperWaveCameraEffectRenderer.render(image, effect: effect, time: effectTime, quality: instruction.quality)
                }
            } else if let face {
                image = try WhisperWaveFaceRenderer.render(image, setting: face, time: effectTime, quality: instruction.quality)
            }
            if opacity < 1 { image = image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))]) }
            result = image.composited(over: result)
        }
        // The editor's dials override the frozen grade while previewing, so a
        // turn redraws the current frame instead of rebuilding the item.
        var filter = instruction.filter
        var adjustments = instruction.adjustments
        var fx = instruction.activeFX(at: time.seconds)
        var captionY = instruction.captionY
        var captionScale = instruction.captionScale
        if instruction.quality == .preview, let live = WhisperWaveLiveGrade.shared.override {
            filter = live.filter
            adjustments = live.adjustments
            fx = live.fx.flatMap { setting in
                if let window = instruction.fxWindow, setting.clipID != nil, !window.contains(time.seconds) { return nil }
                return setting
            }
            if let layout = live.captionLayout {
                captionY = layout.y
                captionScale = layout.scale
            }
        }
        result = adjustments.process(result, filter: filter)
        // Fun effects sit above the color grade and beneath the text, so VHS
        // noise is not re-tinted and captions never shake or pixelate.
        if let fx {
            result = WhisperWaveFXRenderer.shared.render(result, fx: fx, time: time.seconds, quality: instruction.quality)
        }
        // Captions ride above the effects (never shaken or pixelated) and
        // beneath the user's own text layers and stickers.
        let seconds = time.seconds
        for caption in instruction.captionFrames where caption.start <= seconds && seconds < caption.end {
            if let art = caption.frame(at: seconds, canvas: instruction.canvas, y: captionY, scale: captionScale) { result = art.composited(over: result) }
        }
        for text in instruction.textFrames {
            if let art = text.frame(at: time.seconds, canvas: instruction.canvas) { result = art.composited(over: result) }
        }
        return result.cropped(to: canvas)
    }
}
