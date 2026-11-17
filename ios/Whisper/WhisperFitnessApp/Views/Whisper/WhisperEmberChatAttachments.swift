import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// One pending composer attachment for the Jasper chat — a photo (run through
/// Jasper's vision read) or a text-extractable file (plain text, CSV, JSON,
/// markdown, PDF).
struct WhisperEmberChatAttachment: Identifiable, Hashable {
    enum Kind: Hashable {
        case photo(UIImage)
        case file(name: String, text: String)
    }

    let id = UUID()
    let kind: Kind

    var label: String {
        switch kind {
        case .photo: return "Photo"
        case .file(let name, _): return name
        }
    }

    var thumbnail: UIImage? {
        if case .photo(let image) = kind { return image }
        return nil
    }
}

/// Jasper's eyes — describes an attached photo through the vision model so
/// the shared brain (a text endpoint) can ground its reply in what's actually
/// in the image. Same proxy + model as the meal-photo vision path.
enum WhisperEmberVision {

    /// A dense factual read of the photo, or nil when vision is unavailable.
    static func describe(_ image: UIImage) async -> String? {
        guard RorkAIProxy.isConfigured, let dataURL = dataURL(for: image) else { return nil }

        struct VisionContent: Encodable {
            let type: String
            let text: String?
            let image_url: ImageURL?
            struct ImageURL: Encodable { let url: String }
        }
        struct VisionMessage: Encodable {
            let role: String
            let content: [VisionContent]
        }
        struct VisionRequest: Encodable {
            let model: String
            let messages: [VisionMessage]
            let max_tokens: Int
        }

        let prompt = """
        Describe this photo for a fitness + social assistant in 4-8 dense factual sentences: \
        what it shows, any visible text (transcribe it), food (name the dish and estimate portions), \
        exercise or form details, screenshots (summarize their content), physique or progress context. \
        Specific and factual only — no preamble, no advice.
        """
        let req = VisionRequest(
            model: RorkAIProxy.chatModel,
            messages: [
                VisionMessage(role: "system", content: [VisionContent(type: "text", text: "You are Knot's vision reader. Dense factual description only.", image_url: nil)]),
                VisionMessage(role: "user", content: [
                    VisionContent(type: "text", text: prompt, image_url: nil),
                    VisionContent(type: "image_url", text: nil, image_url: .init(url: dataURL))
                ])
            ],
            max_tokens: 420
        )
        var request = RorkAIProxy.chatRequest(timeout: 40)
        guard let body = try? JSONEncoder().encode(req) else { return nil }
        request.httpBody = body
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
              let content = decoded.choices?.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Downscaled JPEG data URL — keeps vision payloads small (≤1024px, q0.6).
    private static func dataURL(for image: UIImage) -> String? {
        let maxDim: CGFloat = 1024
        let largest = max(image.size.width, image.size.height)
        let scale = largest > maxDim ? maxDim / largest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}

/// Extracts prompt-ready text from an attached file. Plain text families read
/// directly; PDFs extract through PDFKit. Content is capped so one file can
/// never blow the context.
enum WhisperEmberFileReader {
    static let allowedTypes: [UTType] = [.plainText, .text, .commaSeparatedText, .json, .pdf]
    private static let characterCap = 12_000

    static func read(_ url: URL) -> WhisperEmberChatAttachment? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else { return nil }
            var text = ""
            for index in 0..<min(doc.pageCount, 24) {
                if let page = doc.page(at: index), let content = page.string {
                    text += content + "\n"
                }
                if text.count > characterCap { break }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return WhisperEmberChatAttachment(kind: .file(name: name, text: String(trimmed.prefix(characterCap))))
        }

        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return WhisperEmberChatAttachment(kind: .file(name: name, text: String(trimmed.prefix(characterCap))))
    }
}
