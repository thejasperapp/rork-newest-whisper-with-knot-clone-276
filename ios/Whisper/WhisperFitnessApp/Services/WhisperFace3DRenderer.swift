import CoreImage
import Foundation
import Metal
import simd

/// Offscreen native 3D rendering, shared by camera, stills, thumbnails and video.
/// Only immutable accessory meshes are cached. No camera pixels or face data persist.
nonisolated final class WhisperFace3DRenderer: @unchecked Sendable {
    static let shared = WhisperFace3DRenderer()
    private let lock = NSLock()
    private var resources: Resources?

    private struct Uniforms {
        var rotation: simd_float4x4
        var canvas: SIMD4<Float>
        var eyes: SIMD4<Float>
        var anchors: SIMD4<Float>
        var animation: SIMD4<Float>
    }
    private struct Mesh {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let count: Int
        let occlusionCount: Int
    }
    private final class Resources {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let colorPipeline: MTLRenderPipelineState
        let depthPipeline: MTLRenderPipelineState
        let depthState: MTLDepthStencilState
        let samples: Int
        var meshes: [String: Mesh] = [:]
        var depthTexture: MTLTexture?
        var multisampleTexture: MTLTexture?

        init() throws {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
                  let library = device.makeDefaultLibrary(),
                  let vertex = library.makeFunction(name: "whisperFace3DVertex"),
                  let fragment = library.makeFunction(name: "whisperFace3DFragment") else { throw WhisperFace3DRenderer.failure() }
            self.device = device; self.queue = queue
            samples = device.supportsTextureSampleCount(4) ? 4 : 1
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex; descriptor.fragmentFunction = fragment
            descriptor.rasterSampleCount = samples
            descriptor.depthAttachmentPixelFormat = .depth32Float
            guard let color = descriptor.colorAttachments[0] else { throw WhisperFace3DRenderer.failure() }
            color.pixelFormat = .bgra8Unorm_srgb
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .one; color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            colorPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            color.writeMask = []
            descriptor.fragmentFunction = nil
            depthPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            let depth = MTLDepthStencilDescriptor()
            depth.depthCompareFunction = .lessEqual; depth.isDepthWriteEnabled = true
            guard let state = device.makeDepthStencilState(descriptor: depth) else { throw WhisperFace3DRenderer.failure() }
            depthState = state
        }
        func mesh(_ effect: WhisperAREffect, includesPortrait: Bool) throws -> Mesh {
            let key = effect.rawValue + (includesPortrait ? "-catalog" : "-camera")
            if let cached = meshes[key] { return cached }
            let source = WhisperFace3DMesh.make(effect, includesPortrait: includesPortrait)
            let vertexBuffer = source.vertices.withUnsafeBytes { bytes -> MTLBuffer? in
                guard let base = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: base, length: bytes.count, options: .storageModeShared)
            }
            let indexBuffer = source.indices.withUnsafeBytes { bytes -> MTLBuffer? in
                guard let base = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: base, length: bytes.count, options: .storageModeShared)
            }
            guard let vertexBuffer, let indexBuffer else { throw WhisperFace3DRenderer.failure() }
            let result = Mesh(vertices: vertexBuffer, indices: indexBuffer, count: source.indices.count, occlusionCount: source.occlusionIndexCount)
            meshes[key] = result
            return result
        }
    }

    func render(_ image: CIImage, effect: WhisperAREffect, frames: [WhisperARProcessor.FaceFrame], time: Double, quality: WhisperWaveRenderQuality, preservesExtent: Bool = false, includesPortrait: Bool = false) throws -> CIImage {
        guard effect.isFace, !frames.isEmpty else { return image }
        let extent = image.extent
        guard [extent.minX, extent.minY, extent.width, extent.height].allSatisfy(\.isFinite), extent.width > 8, extent.height > 8 else { throw Self.failure() }
        let valid = Array(frames.filter { frame in
            [frame.eyeMid.x, frame.eyeMid.y, frame.eyeDistance, frame.angle, frame.yaw, frame.pitch,
             frame.noseTip.x, frame.noseTip.y, frame.mouth.x, frame.mouth.y, frame.mouthOpening].allSatisfy(\.isFinite)
                && frame.eyeDistance > 2 && frame.eyeDistance < max(extent.width, extent.height)
        }.prefix(3))
        guard !valid.isEmpty else { return image }
        var canvas = extent
        if preservesExtent {
            for face in valid {
                let radius = face.eyeDistance * 4.4
                canvas = canvas.union(CGRect(x: face.eyeMid.x-radius, y: face.eyeMid.y-radius, width: radius*2, height: radius*2))
            }
            canvas = canvas.intersection(extent.insetBy(dx: -extent.width, dy: -extent.height)).integral
        }
        let maximum: CGFloat = quality == .preview ? 1024 : 2048
        let scale = min(1, min(maximum / max(canvas.width, canvas.height), sqrt(2_200_000 / (canvas.width*canvas.height))))
        let width = max(1, Int(ceil(canvas.width*scale))), height = max(1, Int(ceil(canvas.height*scale)))
        lock.lock(); defer { lock.unlock() }
        let gpu: Resources
        if let resources { gpu = resources }
        else { gpu = try Resources(); resources = gpu }
        let mesh = try gpu.mesh(effect, includesPortrait: includesPortrait)
        func texture(_ format: MTLPixelFormat, samples: Int, resolved: Bool = false) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            descriptor.sampleCount = samples
            descriptor.textureType = samples > 1 ? .type2DMultisample : .type2D
            descriptor.storageMode = .private
            descriptor.usage = resolved ? [.renderTarget, .shaderRead] : [.renderTarget]
            return gpu.device.makeTexture(descriptor: descriptor)
        }
        // Scratch targets never escape this serialized, completed render pass.
        // The resolved output remains unique because Core Image evaluates lazily.
        if gpu.depthTexture?.width != width || gpu.depthTexture?.height != height || (gpu.samples > 1 && gpu.multisampleTexture == nil) {
            gpu.depthTexture = texture(.depth32Float, samples: gpu.samples)
            gpu.multisampleTexture = gpu.samples > 1 ? texture(.bgra8Unorm_srgb, samples: gpu.samples) : nil
        }
        guard let output = texture(.bgra8Unorm_srgb, samples: 1, resolved: true),
              let depth = gpu.depthTexture,
              let command = gpu.queue.makeCommandBuffer() else { throw Self.failure() }
        let multisample = gpu.multisampleTexture
        if gpu.samples > 1 && multisample == nil { throw Self.failure() }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = multisample ?? output
        pass.colorAttachments[0].resolveTexture = multisample == nil ? nil : output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = multisample == nil ? .store : .multisampleResolve
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.depthAttachment.texture = depth; pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare; pass.depthAttachment.clearDepth = 1
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw Self.failure() }
        encoder.setDepthStencilState(gpu.depthState)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
        let seconds = Float(time.isFinite ? max(0, time).truncatingRemainder(dividingBy: 86_400) : 0)
        // All occluders precede all visible geometry. Relative face size is only
        // an overlap heuristic; this pipeline does not claim measured scene depth.
        for occlusion in [true, false] {
            encoder.setRenderPipelineState(occlusion ? gpu.depthPipeline : gpu.colorPipeline)
            for face in valid {
                let yaw = Float(min(0.9, max(-0.9, face.yaw)))
                let pitch = Float(min(0.65, max(-0.65, face.pitch)))
                let roll = Float(face.angle.truncatingRemainder(dividingBy: .pi * 2))
                let rotation = simd_quatf(angle: roll, axis: [0,0,1]) * simd_quatf(angle: yaw, axis: [0,1,0]) * simd_quatf(angle: pitch, axis: [1,0,0])
                let spacing = Float(face.eyeDistance) / max(0.65, cos(yaw))
                var uniforms = Uniforms(rotation: simd_float4x4(rotation),
                    canvas: [Float(canvas.minX), Float(canvas.minY), Float(canvas.width), Float(canvas.height)],
                    eyes: [Float(face.eyeMid.x), Float(face.eyeMid.y), spacing, 0.72 - min(0.45, Float(face.eyeDistance / max(extent.width, extent.height)))],
                    anchors: [Float(face.noseTip.x), Float(face.noseTip.y), Float(face.mouth.x), Float(face.mouth.y)],
                    animation: [seconds, Float(WhisperARProcessor.puppyTongueAmount(opening: face.mouthOpening)), yaw, pitch])
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                let count = occlusion ? mesh.occlusionCount : mesh.count - mesh.occlusionCount
                let offset = occlusion ? 0 : mesh.occlusionCount * MemoryLayout<UInt32>.stride
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32, indexBuffer: mesh.indices, indexBufferOffset: offset)
            }
        }
        encoder.endEncoding()
        command.commit()
        // The synchronous CI compositor runs on its rendering queue. Never return
        // a lazy CIImage referencing a texture that a later frame will overwrite.
        command.waitUntilCompleted()
        guard command.status == .completed, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let rendered = CIImage(mtlTexture: output, options: [.colorSpace: colorSpace]) else { throw Self.failure() }
        // Metal render targets are top-left; the camera compositor is bottom-left.
        let overlay = rendered.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(height)))
            .transformed(by: CGAffineTransform(scaleX: canvas.width / CGFloat(width), y: canvas.height / CGFloat(height)))
            .transformed(by: CGAffineTransform(translationX: canvas.minX, y: canvas.minY))
        let result: CIImage
        if effect == .halo && !includesPortrait {
            let glow = overlay.applyingGaussianBlur(sigma: max(1, CGFloat(valid[0].eyeDistance) * 0.07))
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.24)])
                .cropped(to: canvas)
            result = overlay.composited(over: glow).composited(over: image)
        } else {
            result = overlay.composited(over: image)
        }
        return preservesExtent ? result : result.cropped(to: extent)
    }

    private static func failure() -> NSError {
        NSError(domain: "WhisperFace3D", code: 1, userInfo: [NSLocalizedDescriptionKey: "The 3D effect couldn't render. Your original is safe. Retry or choose another effect."])
    }
}
