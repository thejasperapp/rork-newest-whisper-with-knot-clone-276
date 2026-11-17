import SwiftUI

/// One-shot floating emoji burst played when a user likes / reposts /
/// shares a post. The emoji is picked from the post's category so a
/// workout post pops a muscle emoji, a business post a briefcase, a
/// celebratory caption a party popper, etc.
///
/// Drives via a single trigger Int — bumping it replays the animation.
/// Pure overlay; never absorbs touches.
struct WhisperReactionBurst: View {
    let emoji: String
    let trigger: Int

    @State private var lastPlayed: Int = 0
    @State private var rise: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.6
    @State private var rotation: Double = -8

    var body: some View {
        Text(emoji)
            .font(.system(size: 44))
            .opacity(opacity)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .offset(y: rise)
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, newValue in
                guard newValue != lastPlayed else { return }
                lastPlayed = newValue
                play()
            }
    }

    private func play() {
        rise = 0
        opacity = 0
        scale = 0.6
        rotation = Double.random(in: -14...14)
        // Pop in.
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            opacity = 1
            scale = 1.1
        }
        // Float up + fade.
        withAnimation(.easeOut(duration: 0.9).delay(0.08)) {
            rise = -68
            opacity = 0
            scale = 0.9
        }
    }
}

/// Maps a post to the emoji that should fly up when the viewer likes,
/// reposts, or shares it. Caption keywords take priority (so a workout
/// post captioned "we won!!!" still gets a party popper), with the
/// post's category kind as the fallback.
enum WhisperReactionEmoji {
    /// Celebratory keywords — these override the category emoji.
    private static let celebration: [String] = [
        "🎉", "🥳", "🎊", "🏆", "won", "winner", "winning",
        "milestone", "achievement", "achieved", "goal", "PR",
        "personal record", "congrats", "congratulations", "huge win",
        "level up", "leveled up", "promoted", "promotion", "graduated",
        "wedding", "engaged", "birthday", "anniversary"
    ]
    private static let businessKeywords: [String] = [
        "💼", "business", "startup", "founder", "ceo", "launch",
        "revenue", "client", "deal", "closed", "funding", "raise",
        "investor", "sales", "pitch", "company", "side hustle"
    ]
    private static let foodKeywords: [String] = [
        "🍽", "🍴", "meal", "recipe", "macro", "protein", "calories",
        "cooking", "cooked", "ate", "dinner", "breakfast", "lunch",
        "snack", "diet"
    ]
    private static let loveKeywords: [String] = [
        "❤️", "love", "💕", "couple", "date night", "partner",
        "boyfriend", "girlfriend", "husband", "wife"
    ]
    private static let travelKeywords: [String] = [
        "✈️", "🌴", "trip", "travel", "flight", "hiking", "mountain"
    ]
    /// Summer / beach / pool keywords — their own bucket so the like
    /// burst pops a beach-ball instead of an airplane. Replaces the older
    /// inline `WhisperBeachBannerCard` (the banner was removed in favor of
    /// a category-specific like animation).
    private static let summerKeywords: [String] = [
        "beach", "summer", "vacation", "vacay", "tropical",
        "poolside", "pool day", "by the pool", "sunny day",
        "ocean", "seaside", "surf", "surfing", "tan lines",
        "boardwalk", "shoreline", "sandy", "palm trees", "sunshine",
        "pool", "sunset", "sunrise"
    ]
    /// Per-community emoji map. Each entry is a tuple of (emoji, keywords)
    /// so a like on a Pets post pops a paw, a Plants post pops a leaf, etc.
    /// Ordered — the first match wins, so most specific topics come first.
    private static let categoryKeywords: [(String, [String])] = [
        ("🐾", ["pet", "pets", "dog", "doggo", "puppy", "cat", "kitten", "kitty", "paw"]),
        ("🌱", ["plant", "plants", "houseplant", "garden", "gardening", "monstera", "succulent", "leaf"]),
        ("🚗", ["car", "cars", "auto", "garage", "drift", "mod", "detailing"]),
        ("🏍️", ["motorcycle", "moto", "motorbike", "rider", "two wheels"]),
        ("🎮", ["gaming", "gamer", "console", "playstation", "xbox", "steam", "speedrun"]),
        ("📚", ["study", "studying", "exam", "finals", "midterm", "school", "college", "university"]),
        ("🎓", ["graduated", "graduation", "diploma", "degree"]),
        ("🎨", ["art", "paint", "painting", "drawing", "sketch", "illustration"]),
        ("🎵", ["music", "song", "album", "playlist", "spotify", "concert"]),
        ("📖", ["book", "reading", "novel", "chapter", "author"]),
        ("🧠", ["mental health", "therapy", "anxiety", "depression", "selfcare", "self-care"]),
        ("🕯️", ["meditation", "mindful", "mindfulness", "breathwork"]),
        ("🔬", ["science", "physics", "biology", "chemistry", "research", "experiment"]),
        ("🚀", ["space", "rocket", "nasa", "spacex", "orbit", "launch day"]),
        ("📰", ["news", "breaking", "politics", "election"]),
        ("😂", ["joke", "meme", "shitpost", "comedy", "standup", "funny"]),
        ("✍️", ["writing", "writer", "essay", "poem", "novel", "draft"]),
        ("🏠", ["home reno", "renovation", "decor", "apartment tour", "new place"]),
        ("🔨", ["diy", "woodwork", "makerspace", "build day", "workshop"]),
        ("🍳", ["baking", "baked", "cookies", "cake", "sourdough", "bread"]),
        ("☕️", ["coffee", "espresso", "latte", "cafe", "café"]),
        ("👶", ["baby", "toddler", "newborn", "parenting", "mom life", "dad life"]),
        ("💍", ["engaged", "engagement", "proposal", "wedding", "married"]),
        ("🗽", ["language", "duolingo", "spanish", "french", "japanese", "korean", "mandarin"]),
        ("🤔", ["philosophy", "stoic", "existential", "big question"]),
        ("📜", ["history", "ancient", "empire", "medieval", "renaissance"]),
        ("🥖", ["date", "dating", "crush", "talking stage", "first date"])
    ]

    static func emoji(forCaption caption: String, kind: WhisperPostKind, action: Action) -> String {
        let c = caption.lowercased()

        func contains(_ list: [String]) -> Bool {
            for k in list {
                if c.contains(k.lowercased()) { return true }
            }
            return false
        }

        // Share/repost always nudges toward "spreading", but we still let
        // celebratory captions override.
        if contains(celebration) { return "🎉" }
        if contains(loveKeywords) { return "❤️" }
        if contains(businessKeywords) { return "💼" }
        // Summer takes priority over travel so a "beach vacay" pops a
        // beach-ball rather than an airplane.
        if contains(summerKeywords) { return "🏖️" }
        if contains(travelKeywords) { return "✈️" }
        if contains(foodKeywords) { return "🍽️" }
        for (emoji, keywords) in categoryKeywords {
            if contains(keywords) { return emoji }
        }

        switch kind {
        case .workout:  return "💪"
        case .progress: return "📈"
        case .grid:     return "⬛️"
        case .photo:
            switch action {
            case .like:   return "❤️"
            case .repost: return "🔁"
            case .share:  return "✈️"
            }
        }
    }

    enum Action { case like, repost, share }
}
