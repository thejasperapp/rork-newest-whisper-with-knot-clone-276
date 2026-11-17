import Foundation

/// Edits the supplied photo only; never substitutes text-to-image after an edit failure.
nonisolated enum WhisperStoryImageEditService {
    private struct Response: Decodable { let images: [String]? }

    static func edit(jpeg: Data, prompt: String, aspectRatio: Double) async throws -> Data {
        try Task.checkCancellation()
        let sized = RorkAIProxy.resizeImageForUpload(jpeg)
        guard sized.count <= 2_500_000, RorkAIProxy.isConfigured else { throw URLError(.dataLengthExceedsMaximum) }
        guard aspectRatio.isFinite, aspectRatio >= 1.0 / 3.0, aspectRatio <= 3 else { throw URLError(.unsupportedURL) }
        let width = Int((sqrt(1_048_576 * aspectRatio) / 16).rounded()) * 16
        let height = Int((Double(width) / aspectRatio / 16).rounded()) * 16
        var request = RorkAIProxy.imageRequest(modelID: RorkAIProxy.imageModel, timeout: 150)
        let payload: [String: Any] = [
            "model": RorkAIProxy.imageModel,
            "prompt": "Edit this supplied photograph. Keep its composition, framing, and aspect ratio unless the requested change requires otherwise. Do not add interface controls or borders. Requested change: \(prompt)",
            "n": 1,
            "size": "\(width)x\(height)",
            "providerOptions": [String: String](),
            "files": [["type": "url", "url": "data:image/jpeg;base64,\(sized.base64EncodedString())"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let raw = decoded.images?.first, let output = Data(base64Encoded: raw) else { throw URLError(.cannotDecodeContentData) }
        return output
    }
}
