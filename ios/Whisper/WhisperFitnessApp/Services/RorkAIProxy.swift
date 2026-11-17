import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Central transport config for every Jasper AI call. The app talks to the
/// Rork Toolkit proxy (Vercel AI Gateway) instead of directly to OpenAI —
/// same OpenAI-compatible request/response shapes, different base URL and
/// auth. Keeping this in one place means every Jasper feature (recipes,
/// image generation, menus, macro estimates, chat guard, diet plans) runs
/// through the working cloud key without touching feature internals.
nonisolated enum RorkAIProxy {
    /// Chat + vision model — same GPT-4o the features were built against,
    /// routed through the gateway (provider-prefixed ID).
    static let chatModel = "openai/gpt-4o"
    /// Cheap classifier model for the DM safety guard.
    static let miniChatModel = "openai/gpt-4o-mini"
    /// Default image generation/editing model on the v3 image endpoint.
    static let imageModel = "openai/gpt-image-2"
    /// Fallback image model if the primary rejects a request.
    static let imageFallbackModel = "openai/gpt-image-1"

    static var secret: String { Config.allValues["EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY"] ?? "" }
    static var isConfigured: Bool { !secret.isEmpty }

    static var baseURL: String {
        var raw = Config.EXPO_PUBLIC_TOOLKIT_URL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { raw = "https://toolkit.rork.com" }
        while raw.hasSuffix("/") { raw = String(raw.dropLast()) }
        return raw.hasPrefix("http") ? raw : "https://\(raw)"
    }

    /// OpenAI-compatible chat completions (text, vision, JSON mode).
    static var chatCompletionsURL: URL {
        URL(string: "\(baseURL)/v2/vercel/v1/chat/completions")!
    }

    /// v3 image-model endpoint for `type: "image"` models (generation and
    /// editing via `files[]`).
    static var imageModelURL: URL {
        URL(string: "\(baseURL)/v2/vercel/v3/ai/image-model")!
    }

    /// Pre-authorized chat completions request. Callers set `httpBody`.
    static func chatRequest(timeout: TimeInterval = 60) -> URLRequest {
        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        return request
    }

    /// Pre-authorized v3 image-model request with the gateway protocol
    /// headers. Callers set `httpBody`.
    static func imageRequest(modelID: String, timeout: TimeInterval = 120) -> URLRequest {
        var request = URLRequest(url: imageModelURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("0.0.1", forHTTPHeaderField: "ai-gateway-protocol-version")
        request.setValue("4", forHTTPHeaderField: "ai-image-model-specification-version")
        request.setValue(modelID, forHTTPHeaderField: "ai-model-id")
        request.timeoutInterval = timeout
        return request
    }

    // MARK: - Image upload sizing

    /// Downscales/re-encodes an image against a byte budget so base64
    /// payloads stay under the gateway's request-body limit. Walks a
    /// pixel-size / JPEG-quality ladder until the encoded bytes fit.
    static func resizeImageForUpload(_ data: Data, maxBytes: Int = 2_500_000) -> Data {
        if data.count <= maxBytes { return data }
        guard let source = CGImageSourceCreateImageSource(data) else { return data }
        let ladder: [(pixels: Int, quality: CGFloat)] = [
            (2048, 0.85), (1536, 0.8), (1024, 0.75), (768, 0.65), (512, 0.6)
        ]
        for step in ladder {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: step.pixels
            ]
            guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { continue }
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, thumb, [kCGImageDestinationLossyCompressionQuality: step.quality] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { continue }
            if out.length <= maxBytes { return out as Data }
        }
        return data
    }

    private static func CGImageSourceCreateImageSource(_ data: Data) -> CGImageSource? {
        ImageIO.CGImageSourceCreateWithData(data as CFData, nil)
    }
}
