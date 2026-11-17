import SwiftUI

/// THE Whisper gradient — the one brand sweep every surface shares, on both
/// apps: the LIVE gradient. Rose → live orange → amber glow — the exact sweep
/// the LIVE rings, LIVE badges, and "Go Live" already wear, promoted to the
/// brand. Matches `WHISPER_BRAND_GRADIENT` on web 1:1 (`lib/brand.ts`).
/// Use this instead of ad-hoc gradients so the algorithm headline, the Waves
/// tab mark, the paywalls, the "Post wave" button, the type-in text, and every
/// future premium moment read as the same brand.
enum WhisperBrandGradient {
    /// Ordered stops — live rose first, amber glow last.
    static let colors: [Color] = [
        Color(red: 0.949, green: 0.149, blue: 0.349), // #F22659 live rose
        Color(red: 1.000, green: 0.451, blue: 0.251), // #FF7340 live orange
        Color(red: 1.000, green: 0.663, blue: 0.302)  // #FFA94D amber glow
    ]

    /// Left → right — text fills, headlines, progress bars.
    static var linear: LinearGradient {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    /// Top-leading → bottom-trailing — buttons, tiles, icon chips.
    static var diagonal: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Top → bottom — hero washes and scrims.
    static var vertical: LinearGradient {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    /// A seamless conic sweep (wraps back to rose) — rings and dials.
    static var angular: AngularGradient {
        AngularGradient(colors: colors + [colors[0]], center: .center, angle: .degrees(210))
    }

    /// The live-orange mid-stop — the single accent when one color has to stand in.
    static let accent: Color = Color(red: 1.000, green: 0.451, blue: 0.251)
    /// The amber end-stop.
    static let amber: Color = Color(red: 1.000, green: 0.663, blue: 0.302)
    /// The rose start-stop.
    static let rose: Color = Color(red: 0.949, green: 0.149, blue: 0.349)

    // Legacy names kept so older call sites keep compiling on the new sweep.
    static let indigo: Color = Color(red: 0.949, green: 0.149, blue: 0.349)
    static let mint: Color = Color(red: 1.000, green: 0.663, blue: 0.302)
}
