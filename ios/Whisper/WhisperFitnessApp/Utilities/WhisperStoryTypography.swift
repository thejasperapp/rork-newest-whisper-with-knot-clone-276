import SwiftUI

/// Shared canvas and typing typography; optional fields leave legacy stories unchanged.
enum WhisperStoryTypography {
    static func font(_ name: String?, size: Double, style: Int = 0) -> Font {
        let size = min(80, max(12, size))
        switch name {
        case "editorial": return .custom("Didot", size: size)
        case "typewriter": return .system(size: size, weight: .medium, design: .monospaced)
        case "rounded": return .system(size: size, weight: .bold, design: .rounded)
        case "serif": return .system(size: size, weight: .regular, design: .serif)
        default:
            if style == 5 { return .system(size: size, weight: .bold, design: .monospaced) }
            return .system(size: size, weight: style == 4 ? .black : .heavy)
        }
    }
    static func alignment(_ raw: String?) -> TextAlignment {
        raw == "leading" ? .leading : raw == "trailing" ? .trailing : .center
    }
}
