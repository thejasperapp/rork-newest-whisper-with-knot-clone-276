import Foundation

/// An illustration is a composition, not a badge pasted onto a shared drawing.
nonisolated enum WhisperIllustrationKind: String, CaseIterable {
    case messages, replies, groups, posts, photos, waves, search, people, saved, notes
    case audio, calendar, activity, files, fitness, food, shopping, places, safety
    case stickers, awards, map, ideas, studio, live, likes, reposts

    static func forSymbol(_ symbol: String) -> Self {
        if symbol.contains("banknote") { return .shopping }
        if symbol.contains("dumbbell") { return .fitness }
        if symbol == "text.bubble" { return .posts }
        if symbol.contains("paperplane") || symbol.contains("envelope") { return .messages }
        if symbol.contains("person.3") { return .groups }
        if symbol.contains("person") && (symbol.contains("slash") || symbol.contains("xmark")) { return .safety }
        if symbol.contains("person") || symbol.contains("hands") { return .people }
        if symbol.contains("bubble") { return .replies }
        if symbol.contains("photo") { return .photos }
        if symbol.contains("film") { return .studio }
        if symbol.contains("play") || symbol.contains("video") { return .waves }
        if symbol.contains("magnifyingglass") || symbol.contains("binocular") || symbol == "number" { return .search }
        if symbol.contains("bookmark") { return .saved }
        if symbol.contains("folder") || symbol.contains("tray") { return .files }
        if symbol.contains("doc") || symbol.contains("note") { return .notes }
        if symbol.contains("waveform") || symbol.contains("music") || symbol.contains("headphone") { return .audio }
        if symbol.contains("calendar") || symbol.contains("clock") { return .calendar }
        if symbol.contains("bell") { return .activity }
        if symbol.contains("dumbbell") || symbol.contains("figure") || symbol.contains("rectangle.stack") { return .fitness }
        if symbol.contains("fork") || symbol.contains("book") || symbol.contains("leaf") { return .food }
        if symbol.contains("cart") || symbol.contains("banknote") || symbol.contains("bag") { return .shopping }
        if symbol.contains("building") || symbol.contains("storefront") { return .places }
        if symbol.contains("shield") || symbol.contains("lock") || symbol.contains("minus") || symbol.contains("seal") { return .safety }
        if symbol.contains("face") || symbol.contains("sparkle") { return .stickers }
        if symbol.contains("trophy") || symbol.contains("medal") { return .awards }
        if symbol.contains("map") || symbol.contains("globe") || symbol.contains("chart") { return .map }
        if symbol.contains("radio") || symbol.contains("mic") { return .live }
        if symbol.contains("heart") || symbol.contains("eye") { return .likes }
        if symbol.contains("arrow.2") { return .reposts }
        return .ideas
    }
}
