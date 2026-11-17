import SwiftUI

/// Small, portable design recipe: authored motif plus optional AI-selected custom pigment.
nonisolated struct WhisperChatThemeDesign: Codable, Equatable, Sendable {
    var version: Int = 1
    let preset: String
    let title: String
    var accent_hex: String? = nil

    init(theme: WhisperChatAppearance) { preset = theme.rawValue; title = theme.title }
    var appearance: WhisperChatAppearance { WhisperChatAppearance(rawValue: preset) ?? .classic }
    var isValid: Bool {
        version == 1 && WhisperChatAppearance(rawValue: preset) != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 48 &&
        (accent_hex == nil || accent_hex?.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil)
    }

    @MainActor func palette(_ scheme: ColorScheme) -> WhisperChatPalette {
        guard isValid, let hex = accent_hex, let value = UInt32(hex.dropFirst(), radix: 16) else { return appearance.palette(scheme) }
        let r = Double((value >> 16) & 255)/255, g = Double((value >> 8) & 255)/255, b = Double(value & 255)/255
        func tint(_ base: Double, _ amount: Double) -> Color {
            Color(.sRGB, red: base*(1-amount)+r*amount, green: base*(1-amount)+g*amount, blue: base*(1-amount)+b*amount, opacity: 1)
        }
        // Bound brightness rather than trusting AI text colors: white on sent stays readable.
        return .init(canvas: tint(scheme == .dark ? 0.055 : 0.98, scheme == .dark ? 0.12 : 0.08),
                     outgoing: tint(0, 0.46), incoming: tint(scheme == .dark ? 0.12 : 1, scheme == .dark ? 0.15 : 0.035),
                     outgoingText: .white, incomingText: scheme == .dark ? .white : .black, accent: tint(scheme == .dark ? 0.6 : 0.2, 0.5))
    }
}
