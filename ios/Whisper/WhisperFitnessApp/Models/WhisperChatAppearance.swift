import SwiftUI

/// Built-in artwork families. DMs keep personal preferences; groups use confirmed shared designs.
nonisolated enum WhisperChatAppearance: String, CaseIterable, Identifiable {
    case classic, midnight, rose, ocean, forest, sand, dusk, cherry, lavender, mint, coffee, sky
    case lantern, tide, nocturne, wildflower, blueprint, terracotta
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lantern: "Paper lantern"
        case .tide: "Tidal glass"
        case .nocturne: "After hours"
        case .wildflower: "Wildflower"
        default: rawValue.capitalized
        }
    }

    @MainActor var color: Color {
        switch self {
        case .lantern: return WhisperChatPalette.rgb(0xAE7042)
        case .tide: return WhisperChatPalette.rgb(0x3C8380)
        case .nocturne: return WhisperChatPalette.rgb(0xAA795F)
        case .wildflower: return WhisperChatPalette.rgb(0x718457)
        case .blueprint: return WhisperChatPalette.rgb(0x4477A3)
        case .terracotta: return WhisperChatPalette.rgb(0xAB604B)
        case .classic: return .gray
        case .midnight: return Color(red: 0.20, green: 0.29, blue: 0.49)
        case .rose: return Color(red: 0.75, green: 0.35, blue: 0.48)
        case .ocean: return Color(red: 0.12, green: 0.47, blue: 0.67)
        case .forest: return Color(red: 0.25, green: 0.47, blue: 0.34)
        case .sand: return Color(red: 0.64, green: 0.49, blue: 0.32)
        case .dusk: return Color(red: 0.58, green: 0.37, blue: 0.42)
        case .cherry: return Color(red: 0.70, green: 0.19, blue: 0.29)
        case .lavender: return Color(red: 0.51, green: 0.43, blue: 0.66)
        case .mint: return Color(red: 0.26, green: 0.62, blue: 0.53)
        case .coffee: return Color(red: 0.43, green: 0.31, blue: 0.24)
        case .sky: return Color(red: 0.31, green: 0.59, blue: 0.77)
        }
    }

    @MainActor static func load(thread: String) -> Self {
        Self(rawValue: AccountStorage.string(forKey: "whisper.chatTheme.\(thread.lowercased())") ?? "") ?? .classic
    }
    @MainActor func save(thread: String) {
        AccountStorage.set(rawValue, forKey: "whisper.chatTheme.\(thread.lowercased())")
    }
}
