import Foundation

/// The Dating hub's match engine v2 — pure on-device text math (no AI call,
/// no credits) that turns icebreaker ANSWERS into a compatibility score:
///   • stem-lite tokens (plurals/-ing/-ed folded) with stopwords dropped
///   • a THEME lexicon (outdoors, fitness, food, travel, …) so "hiking" and
///     "trail runs" resonate even when the words differ — cosine over theme
///     vectors + a shared-theme bonus
///   • Jaccard over the raw tokens for literal overlap
///   • +0.3 when both answered the SAME prompt
///   • preference boosts when the person is inside my radius / shares my intent
/// Mirrors web `lib/datingEngine.ts` EXACTLY — same lexicon, same weights.
enum WhisperDatingMatch {
    struct Answer {
        let prompt: String?
        let text: String
    }

    struct Theme {
        let id: String
        let label: String
        let words: [String]
    }

    /// The lexicon — identical order/words on web. Words are normalized
    /// through the same stemmer at lookup, so plural/-ing forms match.
    static let themes: [Theme] = [
        Theme(id: "outdoors", label: "Outdoors", words: ["hike", "hiking", "trail", "trails", "camp", "camping", "mountain", "mountains", "beach", "surf", "surfing", "ski", "skiing", "snowboard", "kayak", "nature", "sunrise", "sunset", "lake", "ocean", "outdoors", "outdoor"]),
        Theme(id: "fitness", label: "Fitness", words: ["gym", "lift", "lifting", "workout", "workouts", "run", "running", "runner", "marathon", "crossfit", "yoga", "pilates", "climb", "climbing", "cycling", "bike", "biking", "training", "athlete", "fitness", "fit", "sweat"]),
        Theme(id: "food", label: "Food", words: ["cook", "cooking", "chef", "restaurant", "restaurants", "brunch", "tacos", "sushi", "pizza", "coffee", "wine", "bake", "baking", "foodie", "dinner", "ramen", "pasta", "recipe", "recipes", "eat", "eating", "snack", "dessert"]),
        Theme(id: "travel", label: "Travel", words: ["travel", "traveling", "travelling", "trip", "trips", "countries", "passport", "flight", "flights", "adventure", "explore", "exploring", "backpacking", "roadtrip", "abroad", "wander"]),
        Theme(id: "music", label: "Music", words: ["music", "concert", "concerts", "festival", "festivals", "vinyl", "guitar", "piano", "sing", "singing", "karaoke", "playlist", "playlists", "dj", "band", "bands", "song", "songs"]),
        Theme(id: "film", label: "Film & TV", words: ["movie", "movies", "film", "films", "cinema", "netflix", "series", "show", "shows", "anime", "documentary", "documentaries", "binge"]),
        Theme(id: "books", label: "Books", words: ["book", "books", "reading", "read", "novel", "novels", "poetry", "library", "writer", "writing", "bookstore"]),
        Theme(id: "art", label: "Art & design", words: ["art", "artist", "paint", "painting", "draw", "drawing", "museum", "gallery", "design", "designer", "photography", "photo", "photos", "creative", "pottery"]),
        Theme(id: "games", label: "Games", words: ["game", "games", "gaming", "gamer", "chess", "board", "boardgames", "nintendo", "playstation", "xbox", "dnd", "puzzle", "puzzles", "trivia"]),
        Theme(id: "pets", label: "Pets & plants", words: ["dog", "dogs", "puppy", "cat", "cats", "kitten", "pet", "pets", "plant", "plants", "garden", "gardening"]),
        Theme(id: "faith", label: "Faith & mindfulness", words: ["church", "faith", "god", "jesus", "pray", "prayer", "spiritual", "spirituality", "meditation", "meditate", "mindful", "mindfulness"]),
        Theme(id: "family", label: "Family & commitment", words: ["family", "kids", "children", "marriage", "married", "settle", "serious", "partner", "partnership", "commitment", "commit", "longterm", "forever"]),
        Theme(id: "nightlife", label: "Nightlife", words: ["bar", "bars", "club", "clubbing", "party", "parties", "drinks", "cocktails", "dancing", "dance", "nightlife"]),
        Theme(id: "homebody", label: "Cozy nights", words: ["cozy", "home", "couch", "chill", "quiet", "introvert", "tea", "candles", "sunday", "blanket", "pajamas", "homebody"]),
        Theme(id: "ambition", label: "Ambition", words: ["career", "business", "startup", "founder", "hustle", "goals", "goal", "ambitious", "driven", "entrepreneur", "work", "working", "grind"]),
        Theme(id: "humor", label: "Humor", words: ["funny", "laugh", "laughing", "laughs", "jokes", "joke", "humor", "sarcastic", "witty", "banter", "memes", "meme", "silly", "goofy"]),
        Theme(id: "kindness", label: "Kindness & honesty", words: ["kind", "kindness", "honest", "honesty", "loyal", "loyalty", "genuine", "respect", "respectful", "empathy", "gentle", "communication", "trust", "trustworthy"]),
        Theme(id: "sports", label: "Sports", words: ["football", "soccer", "basketball", "baseball", "hockey", "tennis", "golf", "nfl", "nba", "fan", "team", "teams", "pickleball"]),
        Theme(id: "wellness", label: "Wellness", words: ["health", "healthy", "sleep", "sober", "therapy", "growth", "journaling", "journal", "wellness", "balance", "selfcare"]),
        Theme(id: "spontaneous", label: "Spontaneity", words: ["spontaneous", "adventurous", "random", "impulsive", "lastminute", "yes"])
    ]

    private static let stopwords: Set<String> = [
        "the", "and", "for", "you", "your", "with", "that", "this", "have", "has",
        "was", "are", "but", "not", "its", "out", "about", "into", "just", "like",
        "them", "they", "then", "than", "what", "when", "where", "would", "could",
        "should", "really", "very", "been", "being", "from", "some", "something",
        "someone", "honestly", "actually", "thing", "things", "love", "loves",
        "want", "wants", "good", "great", "much", "more", "also", "always"
    ]

    /// Theme word → theme index, normalized once.
    private static let themeIndex: [String: Int] = {
        var map: [String: Int] = [:]
        for (i, theme) in themes.enumerated() {
            for word in theme.words { map[stem(word)] = i }
        }
        return map
    }()

    /// Stem-lite — folds plurals and -ing/-ed so "hiking" ≈ "hike". Same rules on web.
    static func stem(_ raw: String) -> String {
        var w = raw
        if w.count > 5, w.hasSuffix("ing") {
            w = String(w.dropLast(3))
            if w.count > 2, w.last == w.dropLast().last { w = String(w.dropLast()) }  // running → run
        } else if w.count > 4, w.hasSuffix("ies") {
            w = String(w.dropLast(3)) + "y"
        } else if w.count > 4, w.hasSuffix("es") {
            w = String(w.dropLast(2))
        } else if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") {
            w = String(w.dropLast())
        } else if w.count > 4, w.hasSuffix("ed") {
            w = String(w.dropLast(2))
        }
        return w
    }

    /// Splits a caption into (the matched icebreaker prompt, the answer text).
    static func answer(from caption: String) -> Answer {
        let clean = WhisperPostMeta.strip(from: caption).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return Answer(prompt: nil, text: "") }
        let lines = clean.components(separatedBy: "\n")
        let first = lines[0].trimmingCharacters(in: .whitespaces)
        let known = WhisperCommunity.datingIcebreakers.first {
            $0.caseInsensitiveCompare(first) == .orderedSame
        }
        if let known, lines.count > 1 {
            let rest = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { return Answer(prompt: known, text: rest) }
        }
        return Answer(prompt: nil, text: clean)
    }

    static func tokens(_ s: String) -> Set<String> {
        let parts = s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { $0.count > 2 && !stopwords.contains($0) }.map(stem))
    }

    /// Theme hits for a token set — theme id → count.
    static func themeVector(_ tokens: Set<String>) -> [Int: Double] {
        var v: [Int: Double] = [:]
        for t in tokens {
            if let i = themeIndex[t] { v[i, default: 0] += 1 }
        }
        return v
    }

    private static func cosine(_ a: [Int: Double], _ b: [Int: Double]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var dot = 0.0
        for (k, va) in a { if let vb = b[k] { dot += va * vb } }
        let na = a.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        let nb = b.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na * nb)
    }

    /// Answer-to-answer resonance (0…~1.3).
    static func similarity(mine: Answer, theirs: Answer) -> Double {
        guard !theirs.text.isEmpty, !mine.text.isEmpty else { return 0 }
        let a = tokens(mine.text)
        let b = tokens(theirs.text)
        var jaccard = 0.0
        if !a.isEmpty, !b.isEmpty {
            let inter = a.intersection(b).count
            let union = a.union(b).count
            if union > 0 { jaccard = Double(inter) / Double(union) }
        }
        let ta = themeVector(a)
        let tb = themeVector(b)
        let cos = cosine(ta, tb)
        let shared = Set(ta.keys).intersection(tb.keys).count
        var score = 0.45 * jaccard + 0.35 * cos + 0.20 * min(1.0, Double(shared) / 3.0)
        if let mp = mine.prompt, let tp = theirs.prompt,
           mp.caseInsensitiveCompare(tp) == .orderedSame {
            score += 0.3
        }
        return score
    }

    /// Convenience: my answer vs a raw caption.
    static func similarity(mine: Answer, caption: String) -> Double {
        similarity(mine: mine, theirs: answer(from: caption))
    }

    /// Best resonance between ANY of my answers and a caption.
    static func bestSimilarity(mine: [Answer], caption: String) -> Double {
        let theirs = answer(from: caption)
        return mine.map { similarity(mine: $0, theirs: theirs) }.max() ?? 0
    }

    /// Theme labels both sides light up on (up to 3) — the "why" chip.
    static func sharedThemes(mine: [Answer], theirsText: String) -> [String] {
        var myThemes: Set<Int> = []
        for a in mine { myThemes.formUnion(themeVector(tokens(a.text)).keys) }
        let theirThemes = Set(themeVector(tokens(theirsText)).keys)
        return myThemes.intersection(theirThemes).sorted().prefix(3).map { themes[$0].label }
    }

    /// Preference boost for someone I know is inside my radius / shares my intent.
    static func prefsBoost(nearby: WhisperDatingNearbyPerson?, prefs: WhisperDatingPrefs) -> Double {
        guard let nearby else { return 0 }
        var boost = 0.0
        if let d = nearby.distance_km, prefs.hasLocation, !prefs.isAnywhere {
            boost += 0.15 * max(0, 1 - min(1, d / Double(max(1, prefs.radiusKm))))
        } else if nearby.distance_km != nil {
            boost += 0.05
        }
        if let mine = prefs.intent, let theirs = nearby.intent, mine == theirs { boost += 0.10 }
        return boost
    }

    /// The person-level score the For-you sort ranks by.
    static func personScore(
        myAnswers: [Answer],
        caption: String,
        nearby: WhisperDatingNearbyPerson?,
        prefs: WhisperDatingPrefs
    ) -> Double {
        bestSimilarity(mine: myAnswers, caption: caption) + prefsBoost(nearby: nearby, prefs: prefs)
    }
}
