import SwiftUI

/// Opaque bubble colors keep contrast independent of the wallpaper underneath.
struct WhisperChatPalette {
    let canvas: Color
    let outgoing: Color
    let incoming: Color
    let outgoingText: Color
    let incomingText: Color
    let accent: Color

    func fill(mine: Bool) -> Color { mine ? outgoing : incoming }
    func text(mine: Bool) -> Color { mine ? outgoingText : incomingText }

    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

extension WhisperChatAppearance {
    @MainActor func palette(_ scheme: ColorScheme) -> WhisperChatPalette {
        if self == .classic {
            return WhisperChatPalette(canvas: scheme == .dark ? .black : .white,
                outgoing: WhisperChatPalette.rgb(scheme == .dark ? 0xB7CCE9 : 0xD3E1F6),
                incoming: WhisperChatPalette.rgb(scheme == .dark ? 0x2C3038 : 0xEAE9EE),
                outgoingText: WhisperChatPalette.rgb(0x161D28),
                incomingText: scheme == .dark ? .white : WhisperChatPalette.rgb(0x17171B), accent: WhisperChatPalette.rgb(0x5279AB))
        }
        let colors: (paper: UInt32, night: UInt32, sent: UInt32, received: UInt32, raised: UInt32)
        switch self {
        case .lantern: colors = (0xF9F1DF, 0x262019, 0x78512C, 0xFFFCF4, 0x403428)
        case .tide: colors = (0xEDF7F3, 0x102825, 0x245B58, 0xF8FFFC, 0x28433F)
        case .nocturne: colors = (0xF0ECE8, 0x191C23, 0x5F493E, 0xFAF8F4, 0x32323A)
        case .wildflower: colors = (0xF3F3E7, 0x20281B, 0x465C32, 0xFDFFF3, 0x36452C)
        case .blueprint: colors = (0xEAF0F8, 0x112237, 0x264D77, 0xF8FBFF, 0x263C55)
        case .terracotta: colors = (0xF9EDE5, 0x2C201D, 0x7D4635, 0xFFF8F1, 0x47322B)
        case .classic: colors = (0xFFFFFF, 0x101010, 0x242424, 0xF2F2F2, 0x292929)
        case .midnight: colors = (0xEAEFF8, 0x101724, 0x293D67, 0xF7F9FF, 0x263349)
        case .rose: colors = (0xFAEFF0, 0x25171F, 0x863C56, 0xFFF9F7, 0x452D3A)
        case .ocean: colors = (0xE9F3F4, 0x10232B, 0x165A70, 0xF5FCFA, 0x233E49)
        case .forest: colors = (0xEDF1E8, 0x14251E, 0x315B45, 0xF8FAF2, 0x2A3F31)
        case .sand: colors = (0xF6EEE0, 0x29221A, 0x705035, 0xFFFAF0, 0x43382A)
        case .dusk: colors = (0xF4EAEF, 0x251E31, 0x684460, 0xFCF6F8, 0x403147)
        case .cherry: colors = (0xFAEDEC, 0x2B171E, 0x923347, 0xFFF8F3, 0x492B34)
        case .lavender: colors = (0xF0ECF7, 0x211E30, 0x5E4C81, 0xFAF8FF, 0x37314B)
        case .mint: colors = (0xE8F4EF, 0x152923, 0x246451, 0xF4FFF9, 0x2A4439)
        case .coffee: colors = (0xF2EAE2, 0x241D19, 0x604332, 0xFFF8ED, 0x403228)
        case .sky: colors = (0xEDF4FC, 0x172536, 0x325E88, 0xFAFCFF, 0x2D3F54)
        }
        func soften(_ pigment: UInt32, base: UInt32, amount: Double) -> Color {
            let channels = [16, 8, 0].map { shift in
                (Double((pigment >> shift) & 255) * amount + Double((base >> shift) & 255) * (1 - amount)).rounded() / 255
            }
            return Color(.sRGB, red: channels[0], green: channels[1], blue: channels[2], opacity: 1)
        }
        return WhisperChatPalette(canvas: scheme == .dark ? .black : soften(colors.paper, base: 0xFAF9F6, amount: 0.5),
            outgoing: soften(colors.sent, base: 0x202729, amount: 0.8), incoming: scheme == .dark ? soften(colors.raised, base: 0x202527, amount: 0.5) : soften(colors.received, base: 0xFFFFFF, amount: 0.3),
            outgoingText: .white, incomingText: WhisperChatPalette.rgb(scheme == .dark ? 0xFFF8F2 : 0x20282A), accent: color)
    }

    var mood: String {
        switch self {
        case .lantern: "Warm paper, pools of amber light"
        case .tide: "Sea glass and flowing contour lines"
        case .nocturne: "Copper orbits after midnight"
        case .wildflower: "A little garden at the edges"
        case .blueprint: "Thoughts worth building together"
        case .terracotta: "Sun-warmed arches and soft clay"
        case .classic: "Quiet & familiar"
        case .midnight: "Under the constellations"
        case .rose: "Pressed petals"
        case .ocean: "A little coastal calm"
        case .forest: "Beneath the canopy"
        case .sand: "Slow desert mornings"
        case .dusk: "The last light"
        case .cherry: "Something sweet"
        case .lavender: "Botanical daydreams"
        case .mint: "Fresh perspectives"
        case .coffee: "Stay for another cup"
        case .sky: "Room to breathe"
        }
    }
}

private struct WhisperChatDesignKey: EnvironmentKey {
    static let defaultValue: WhisperChatThemeDesign? = nil
}

private struct WhisperChatAppearanceKey: EnvironmentKey {
    static let defaultValue: WhisperChatAppearance = .classic
}
extension EnvironmentValues {
    var whisperChatDesign: WhisperChatThemeDesign? {
        get { self[WhisperChatDesignKey.self] }
        set { self[WhisperChatDesignKey.self] = newValue }
    }
    var whisperChatAppearance: WhisperChatAppearance {
        get { self[WhisperChatAppearanceKey.self] }
        set { self[WhisperChatAppearanceKey.self] = newValue }
    }
}
