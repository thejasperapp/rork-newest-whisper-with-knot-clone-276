import Foundation

/// Lightweight, on-device spam detector for inbox messages. Scores a message
/// 0…1 based on common spam signals (sketchy keywords, links, excessive caps,
/// repeated characters, OF/crypto/forwarded-money patterns). Thread is treated
/// as spam if the score crosses `threshold` AND the sender is NOT a mutual.
///
/// Intentionally rule-based — fast, deterministic, no network calls. Easy to
/// tune by adding/removing keywords.
nonisolated enum WhisperSpamFilter {
    static let threshold: Double = 0.6

    private static let spamKeywords: [String] = [
        "onlyfans", "only fans", "of model", "of creator",
        "bitcoin", "btc", "crypto", "eth ", "usdt", "binance", "coinbase",
        "click here", "click the link", "tap the link", "link in bio",
        "telegram me", "whatsapp me", "dm for", "hmu for",
        "free money", "easy money", "make $", "earn $", "earn upto",
        "investment opportunity", "trading signals", "forex",
        "winner", "you have been selected", "congratulations you",
        "verify your account", "suspended", "claim your prize",
        "nudes", "horny", "spicy content", "leaked",
        "promo code", "discount code", "sub to my",
    ]

    static func score(message: String, senderUsername: String? = nil) -> Double {
        let lc = message.lowercased()
        guard !lc.isEmpty else { return 0 }
        var score = 0.0

        for kw in spamKeywords where lc.contains(kw) {
            score += 0.3
        }

        // URL-ish patterns (http, www, bare TLDs, t.me, bit.ly, etc.)
        let urlPatterns = ["http://", "https://", "www.", "t.me/", "bit.ly", ".com/", ".io/", ".xyz", ".gg/", ".onelink"]
        if urlPatterns.contains(where: { lc.contains($0) }) {
            score += 0.3
        }

        // Excessive caps (only counts for messages with real letters)
        let letters = message.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        if letters.count >= 10 {
            let upper = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
            let ratio = Double(upper) / Double(letters.count)
            if ratio > 0.7 { score += 0.2 }
        }

        // Repeated character runs (aaaaaa, $$$$$, !!!!!)
        if message.range(of: #"(.)\1{5,}"#, options: .regularExpression) != nil {
            score += 0.2
        }

        // Many emoji-dollar or money signs
        let dollarCount = message.filter { $0 == "$" }.count
        if dollarCount >= 3 { score += 0.2 }

        // Suspicious username patterns (e.g. randomish strings of digits)
        if let u = senderUsername?.lowercased() {
            if u.range(of: #"[a-z]+\d{4,}"#, options: .regularExpression) != nil {
                score += 0.1
            }
        }

        return min(1.0, score)
    }

    static func isSpam(message: String, senderUsername: String? = nil) -> Bool {
        score(message: message, senderUsername: senderUsername) >= threshold
    }

    /// Session-scoped verdict memo. The inbox re-evaluates the spam
    /// predicate several times per thread per render (each filter chip's
    /// badge count walks the full thread list), so verdicts are cached by
    /// (sender, message). Bounded — clears wholesale past 500 entries.
    @MainActor private static var verdictCache: [String: Bool] = [:]

    @MainActor
    static func cachedIsSpam(message: String, senderUsername: String? = nil) -> Bool {
        let key = "\(senderUsername ?? "")|\(message)"
        if let hit = verdictCache[key] { return hit }
        let verdict = isSpam(message: message, senderUsername: senderUsername)
        if verdictCache.count > 500 { verdictCache.removeAll(keepingCapacity: true) }
        verdictCache[key] = verdict
        return verdict
    }
}
