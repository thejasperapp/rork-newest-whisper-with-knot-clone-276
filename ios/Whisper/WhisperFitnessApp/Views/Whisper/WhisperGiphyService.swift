import Foundation

/// Native Giphy API wrapper used by the GIF picker. Calls Giphy's public
/// REST endpoints (trending, categories, search) and exposes them as
/// async helpers. The API key is injected at build time from
/// `EXPO_PUBLIC_GIPHY_API_KEY` via `Config.swift`.
///
/// We intentionally hit the lightweight `fixed_height` rendition so the
/// grid loads quickly over cellular, falling back to `downsized_medium`
/// or the original URL when smaller renditions are absent.
nonisolated struct WhisperGiphyService: Sendable {
    static let shared = WhisperGiphyService()

    private var apiKey: String { Config.allValues["EXPO_PUBLIC_GIPHY_API_KEY"] ?? "" }
    private var base: URL { URL(string: "https://api.giphy.com/v1/gifs")! }

    /// One named bucket in the picker (a category or "Trending").
    struct Category: Sendable, Hashable, Identifiable {
        let name: String
        let displayName: String
        var id: String { name }
    }

    /// Native Giphy categories. Trending is synthesized client-side so it
    /// always appears as the first chip, regardless of API state.
    func fetchCategories() async -> [Category] {
        let fallback: [Category] = [
            .init(name: "trending",   displayName: "Trending"),
            .init(name: "reactions",  displayName: "Reactions"),
            .init(name: "sports",     displayName: "Sports"),
            .init(name: "tv",         displayName: "TV"),
            .init(name: "memes",      displayName: "Memes"),
            .init(name: "animals",    displayName: "Animals"),
            .init(name: "music",      displayName: "Music"),
            .init(name: "gaming",     displayName: "Gaming"),
            .init(name: "love",       displayName: "Love"),
            .init(name: "celebrities", displayName: "Celebrities")
        ]
        guard !apiKey.isEmpty,
              var comp = URLComponents(url: base.appendingPathComponent("categories"), resolvingAgainstBaseURL: false)
        else { return fallback }
        comp.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        guard let url = comp.url else { return fallback }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(CategoriesResponse.self, from: data)
            var cats: [Category] = [.init(name: "trending", displayName: "Trending")]
            for c in decoded.data {
                let display = c.name.prefix(1).uppercased() + c.name.dropFirst()
                cats.append(.init(name: c.name, displayName: String(display)))
            }
            return cats
        } catch {
            return fallback
        }
    }

    /// Fetches GIFs for a category. `"trending"` hits the trending endpoint;
    /// everything else hits search with the category name as the query so
    /// we get fresh, on-trend results without depending on Giphy's curated
    /// per-category endpoint (which is sometimes empty for niche tags).
    func fetchGifs(for category: String, limit: Int = 30) async -> [WhisperGif] {
        await fetch(kind: .gifs, category: category, limit: limit)
    }

    /// Free-form search invoked when the user types in the picker's search
    /// bar. Returns an empty list for blank queries so we fall back to the
    /// category grid.
    func search(_ query: String, limit: Int = 30) async -> [WhisperGif] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return await fetchGifs(for: trimmed, limit: limit)
    }

    // MARK: - Stickers

    /// Animated transparent stickers (same endpoint shape as GIFs but under
    /// `/v1/stickers/...`). These are the actual Threads-style animated
    /// stickers — transparent backgrounds, mostly looping characters.
    func fetchStickers(for category: String, limit: Int = 30) async -> [WhisperGif] {
        await fetch(kind: .stickers, category: category, limit: limit)
    }

    func searchStickers(_ query: String, limit: Int = 30) async -> [WhisperGif] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return await fetchStickers(for: trimmed, limit: limit)
    }

    /// Giphy doesn't expose a sticker categories endpoint, so we curate a
    /// list of popular sticker tags that always return rich results.
    func stickerCategories() -> [Category] {
        [
            .init(name: "trending",  displayName: "Trending"),
            .init(name: "reactions", displayName: "Reactions"),
            .init(name: "love",      displayName: "Love"),
            .init(name: "happy",     displayName: "Happy"),
            .init(name: "sad",       displayName: "Sad"),
            .init(name: "yes",       displayName: "Yes"),
            .init(name: "no",        displayName: "No"),
            .init(name: "thanks",    displayName: "Thanks"),
            .init(name: "cute",      displayName: "Cute"),
            .init(name: "workout",   displayName: "Workout"),
            .init(name: "food",      displayName: "Food"),
            .init(name: "animals",   displayName: "Animals"),
            .init(name: "party",     displayName: "Party"),
            .init(name: "hello",     displayName: "Hello")
        ]
    }

    // MARK: - Internal

    private enum Kind: String { case gifs, stickers }

    private func fetch(kind: Kind, category: String, limit: Int) async -> [WhisperGif] {
        guard !apiKey.isEmpty else { return [] }
        let isTrending = category.lowercased() == "trending"
        let path = isTrending ? "trending" : "search"
        let root = URL(string: "https://api.giphy.com/v1/\(kind.rawValue)")!
        var comp = URLComponents(url: root.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "api_key", value: apiKey),
            .init(name: "limit", value: String(limit)),
            .init(name: "rating", value: "pg-13")
        ]
        if kind == .gifs {
            items.append(.init(name: "bundle", value: "messaging_non_clips"))
        }
        if !isTrending {
            items.append(.init(name: "q", value: category))
        }
        comp.queryItems = items
        guard let url = comp.url else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(GifsResponse.self, from: data)
            return decoded.data.compactMap { $0.toWhisperGif() }
        } catch {
            return []
        }
    }

    // MARK: - DTOs

    nonisolated struct CategoriesResponse: Decodable {
        let data: [Item]
        struct Item: Decodable { let name: String }
    }

    nonisolated struct GifsResponse: Decodable {
        let data: [GifItem]
    }

    nonisolated struct GifItem: Decodable {
        let id: String
        let images: Images?

        struct Images: Decodable {
            let fixed_height: Rendition?
            let fixed_height_small: Rendition?
            let downsized_medium: Rendition?
            let original: Rendition?
        }

        struct Rendition: Decodable {
            let url: String?
        }

        func toWhisperGif() -> WhisperGif? {
            let candidates = [
                images?.fixed_height?.url,
                images?.fixed_height_small?.url,
                images?.downsized_medium?.url,
                images?.original?.url
            ]
            guard let raw = candidates.compactMap({ $0 }).first,
                  let url = URL(string: raw) else { return nil }
            return WhisperGif(id: id, url: url)
        }
    }
}

/// Lightweight GIF DTO used by the picker grid + chip preview.
nonisolated struct WhisperGif: Sendable, Identifiable, Hashable {
    let id: String
    let url: URL
}
