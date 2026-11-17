import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Personal wallpaper bytes stay on this device. No image or prompt enters a group theme row.
actor WhisperWallpaperStore {
    static let shared = WhisperWallpaperStore()

    private func location(owner: String, thread: String) throws -> URL {
        guard let user = UUID(uuidString: owner), !thread.isEmpty else { throw URLError(.userAuthenticationRequired) }
        let name = SHA256.hash(data: Data(thread.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("WhisperPersonalWallpapers", isDirectory: true)
            .appendingPathComponent(user.uuidString.lowercased(), isDirectory: true).appendingPathComponent(name + ".jpg")
    }

    func load(owner: String, thread: String) -> Data? {
        guard let url = try? location(owner: owner, thread: thread), let data = try? Data(contentsOf: url), data.count <= 1_500_000 else { return nil }
        return data
    }

    func save(_ data: Data?, owner: String, thread: String) throws {
        try Task.checkCancellation()
        let url = try location(owner: owner, thread: thread)
        guard let data else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        guard data.count <= 1_500_000 else { throw URLError(.dataLengthExceedsMaximum) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Task.checkCancellation()
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Force a bounded, metadata-free JPEG rather than saving a remote URL or original response.
    nonisolated static func prepare(_ data: Data) throws -> Data {
        guard data.count <= 20_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1536] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw URLError(.cannotDecodeContentData) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 1_500_000 else { throw URLError(.dataLengthExceedsMaximum) }
        return output as Data
    }

    nonisolated static func generate(brief: String) async throws -> Data {
        let prompt = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.count <= 400 else { throw URLError(.badURL) }
        var request = RorkAIProxy.imageRequest(modelID: RorkAIProxy.imageModel)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": RorkAIProxy.imageModel, "n": 1, "size": "1024x1536", "providerOptions": [String: String](),
            "prompt": "Create an original elegant chat wallpaper, quiet negative space in the center for readable messages, soft dimensional materials, diffused lighting, no text, no letters, no UI. Design brief: " + prompt
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let images = json["images"] as? [String],
              let first = images.first, first.utf8.count <= 28_000_000, let image = Data(base64Encoded: first) else { throw URLError(.badServerResponse) }
        return try prepare(image)
    }
}
