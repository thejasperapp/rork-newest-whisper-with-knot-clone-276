import Foundation

/// Shared catalog of bundled Whisper stickers. Names map to
/// `WhisperSticker_<name>` imagesets in the main Assets catalog. Used by
/// the story editor sticker tray and the DM/comment sticker picker.
nonisolated enum WhisperStickerPack {
    struct Item: Hashable, Sendable {
        let name: String
        let label: String
        let tags: [String]
    }

    static let all: [Item] = [
        .init(name: "ember", label: "Jasper", tags: ["ember", "mascot", "ai", "cute"]),
        .init(name: "ember_headphones", label: "Jasper Vibing", tags: ["ember", "music", "headphones", "vibe"]),
        .init(name: "ghost_crown", label: "Royalty", tags: ["crown", "king", "queen", "flex"]),
        .init(name: "ghost_king", label: "King", tags: ["king", "crown", "goat"]),
        .init(name: "ghost_bolt", label: "Energized", tags: ["bolt", "hyped", "energy", "lit"]),
        .init(name: "ghost_boost", label: "Boosted", tags: ["boost", "rocket", "hype"]),
        .init(name: "ghost_send", label: "Send It", tags: ["send", "hype", "yes"]),
        .init(name: "ghost_trophy", label: "Winning", tags: ["trophy", "win", "goat"]),
        .init(name: "ghost_beach", label: "Beach Day", tags: ["beach", "summer", "vacation"]),
        .init(name: "jasper_beachball", label: "Beach Ball", tags: ["beach", "ball", "summer", "fun"]),
        .init(name: "ghost_couple", label: "Couple", tags: ["couple", "love", "date"]),
        .init(name: "ghost_home", label: "Home", tags: ["home", "chill", "couch"]),
        .init(name: "ghost_sleepy", label: "Sleepy", tags: ["sleep", "tired", "night"]),
        .init(name: "ghost_sad", label: "Sad", tags: ["sad", "cry", "mood"]),
        .init(name: "ghost_cookie", label: "Cookie", tags: ["cookie", "snack", "hungry"]),
        .init(name: "ghost_book", label: "Reading", tags: ["book", "study", "read"]),
        .init(name: "ghost_dragon", label: "Dragon Rider", tags: ["dragon", "epic", "fantasy"]),
        .init(name: "ghost_kraken", label: "Kraken", tags: ["kraken", "sea", "epic"])
    ]

    /// URL scheme that identifies a bundled Whisper sticker (e.g. when sent
    /// as a DM body). Form: `jasper-sticker://<name>`.
    static let urlScheme: String = "jasper-sticker"

    /// Returns true if the provided URL string is a Whisper sticker.
    static func isWhisperSticker(_ raw: String) -> Bool {
        raw.lowercased().hasPrefix("\(urlScheme)://")
    }

    /// Extracts the sticker name from a `jasper-sticker://<name>` URL or
    /// returns nil if the string doesn't match.
    static func stickerName(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isWhisperSticker(trimmed) else { return nil }
        let prefix = "\(urlScheme)://"
        let name = String(trimmed.dropFirst(prefix.count))
        return name.isEmpty ? nil : name
    }

    /// Asset catalog image name for the given sticker name.
    static func assetName(for stickerName: String) -> String {
        "WhisperSticker_\(stickerName)"
    }

    static func filtered(query: String) -> [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { item in
            item.label.lowercased().contains(q) ||
            item.name.lowercased().contains(q) ||
            item.tags.contains(where: { $0.contains(q) })
        }
    }
}
