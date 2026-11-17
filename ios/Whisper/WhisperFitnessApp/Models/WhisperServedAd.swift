import Foundation

/// Serving DTO shared with the web's business_active_ads RPC.
nonisolated struct WhisperServedAd: Decodable, Identifiable, Sendable {
    let id: String
    let headline: String
    let body: String?
    let image_url: String?
    let video_url: String?
    let media_type: String?
    let cta_label: String
    let cta_url: String?
    let business_name: String
    let business_logo_url: String?
    let business_website: String?

    var destination: URL? { Self.webURL(cta_url) ?? Self.webURL(business_website) }
    var videoURL: URL? { Self.webURL(video_url) }
    var imageURL: URL? { Self.webURL(image_url) }

    static func webURL(_ raw: String?) -> URL? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let normalized = text.contains(":") ? text : "https://\(text)"
        guard let url = URL(string: normalized), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
