import SwiftUI
import UIKit

/// Shared visual language for Jasper's pill surfaces — matched to the
/// reference art: a pale capsule with a clear tracing around the edge, a
/// soft glow, and near-black bold text. Thin proportions. The whole palette
/// adapts to the active personality: mint for the Original, gold for Angel,
/// ember-red for Drill Sergeant, violet for Scientist.
enum WhisperEmberPillPalette {
    /// Pale mint fill — sampled from the reference art (#EFF4F1): nearly
    /// white with the faintest green cast, NOT a saturated mint.
    static let fill = Color(red: 239 / 255, green: 245 / 255, blue: 241 / 255)
    /// The mint tracing around the capsule edge — the reference pastel
    /// (#B9F3DC family), soft rather than saturated.
    static let rim = Color(red: 0.67, green: 0.905, blue: 0.795)
    /// Mint glow colour (Jasper's accent, #34d399).
    static let glow = Color(red: 0.20, green: 0.83, blue: 0.60)
    /// Near-black ink for text and icons on the pale fill.
    static let ink = Color(red: 0.04, green: 0.09, blue: 0.07)
    /// Medium mint for badge glyphs and small accents.
    static let badge = Color(red: 0.24, green: 0.78, blue: 0.58)

    /// Personality-adaptive pale fill.
    static func fill(for mode: WhisperEmberCoachMode) -> Color {
        switch mode.resolved {
        case .auto, .regular: return fill
        case .guardian: return Color(red: 255 / 255, green: 249 / 255, blue: 228 / 255)
        case .drillSergeant: return Color(red: 255 / 255, green: 237 / 255, blue: 233 / 255)
        case .scientist: return Color(red: 240 / 255, green: 237 / 255, blue: 255 / 255)
        }
    }

    /// Personality-adaptive tracing colour.
    static func rim(for mode: WhisperEmberCoachMode) -> Color {
        switch mode.resolved {
        case .auto, .regular: return rim
        case .guardian: return Color(red: 0.94, green: 0.79, blue: 0.42)
        case .drillSergeant: return Color(red: 0.96, green: 0.60, blue: 0.52)
        case .scientist: return Color(red: 0.70, green: 0.62, blue: 0.96)
        }
    }

    /// Personality-adaptive glow — the personality's signature accent.
    static func glow(for mode: WhisperEmberCoachMode) -> Color {
        mode.resolved == .regular ? glow : mode.accent
    }

    /// Personality-adaptive near-black ink (subtly warmed/cooled per mode).
    static func ink(for mode: WhisperEmberCoachMode) -> Color {
        switch mode.resolved {
        case .auto, .regular: return ink
        case .guardian: return Color(red: 0.11, green: 0.08, blue: 0.02)
        case .drillSergeant: return Color(red: 0.13, green: 0.04, blue: 0.03)
        case .scientist: return Color(red: 0.07, green: 0.05, blue: 0.14)
        }
    }

    /// Personality-adaptive badge/accent tone for small glyphs.
    static func badge(for mode: WhisperEmberCoachMode) -> Color {
        mode.resolved == .regular ? badge : mode.deepAccent
    }
}

/// The pill shell — pale personality-tinted fill, glossy top light, a
/// distinct tracing, and a soft glow. Worn by the in-meeting Jasper pill,
/// the assistant box header, and the Jasper chat title pill. Recolours
/// live when the personality changes.
struct WhisperEmberMintShell<S: InsettableShape>: View {
    let shape: S
    /// Softens the glow for small chrome like header capsules.
    var compact: Bool = false
    /// Active personality — drives the fill, tracing, and glow colours.
    var mode: WhisperEmberCoachMode = .regular
    /// Optional costume overrides — the Dating dock's cream/pink pill wears
    /// these; nil keeps the personality palette untouched.
    var fillOverride: Color? = nil
    var rimOverride: Color? = nil
    var glowOverride: Color? = nil

    var body: some View {
        ZStack {
            shape.fill(fillOverride ?? WhisperEmberPillPalette.fill(for: mode))
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.6), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            shape.strokeBorder(
                (rimOverride ?? WhisperEmberPillPalette.rim(for: mode)).opacity(compact ? 0.85 : 0.95),
                lineWidth: 1.5
            )
        }
        .compositingGroup()
        .shadow(
            color: (glowOverride ?? WhisperEmberPillPalette.glow(for: mode)).opacity(compact ? 0.22 : 0.34),
            radius: compact ? 6 : 10,
            y: compact ? 2 : 4
        )
        .shadow(
            color: Color.black.opacity(compact ? 0.08 : 0.13),
            radius: compact ? 4 : 8,
            y: compact ? 2 : 5
        )
        .animation(.easeInOut(duration: 0.35), value: mode)
    }
}

/// The native-Jasper language of the assistant surfaces — fully adaptive:
/// a pale lavender-white canvas in light mode, a deep navy-black canvas in
/// dark mode, both washed with the active personality's glow. Every token
/// resolves per the system appearance, so all Jasper surfaces get light AND
/// dark for free.
enum WhisperEmberSheetTheme {
    /// A colour that resolves differently in light and dark appearance.
    private static func dyn(
        _ light: (CGFloat, CGFloat, CGFloat, CGFloat),
        _ dark: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }

    static let canvas = dyn((0.958, 0.956, 0.972, 1), (0.047, 0.047, 0.078, 1))
    static let mintGlow = dyn((0.79, 0.95, 0.88, 1), (0.10, 0.23, 0.185, 1))
    static let lavenderGlow = dyn((0.86, 0.83, 0.98, 1), (0.19, 0.165, 0.35, 1))
    static let card = dyn((1, 1, 1, 1), (0.125, 0.13, 0.185, 1))
    static let ink = dyn((0.10, 0.10, 0.14, 1), (0.94, 0.95, 0.98, 1))
    static let muted = dyn((0.44, 0.45, 0.52, 1), (0.60, 0.62, 0.70, 1))
    static let hairline = dyn((0, 0, 0, 0.07), (1, 1, 1, 0.09))
    static let violet = dyn((0.44, 0.38, 0.88, 1), (0.63, 0.56, 1.0, 1))
    static let violetSoft = dyn((0.62, 0.57, 0.93, 1), (0.47, 0.42, 0.82, 1))

    /// Soft fill for chips, rows, and quiet buttons.
    static let surface = dyn((0.07, 0.08, 0.12, 0.05), (1, 1, 1, 0.07))
    /// Stronger fill for selected rows and secondary buttons.
    static let surfaceStrong = dyn((0.07, 0.08, 0.12, 0.09), (1, 1, 1, 0.12))
    /// Hairline stroke for chips and fields.
    static let stroke = dyn((0, 0, 0, 0.06), (1, 1, 1, 0.09))
    /// OPAQUE chrome — the title pill the ghost hides behind, header circles.
    static let pillFill = dyn((1, 1, 1, 1), (0.135, 0.14, 0.20, 1))
    static let pillStroke = dyn((0, 0, 0, 0.08), (1, 1, 1, 0.16))
    /// The user's message bubble — Jasper blue in light, soft white on dark.
    static let userBubble = dyn((0.26, 0.47, 0.96, 1), (1, 1, 1, 0.10))
    static let userBubbleInk = dyn((1, 1, 1, 1), (0.94, 0.95, 0.98, 1))
    /// High-contrast primary action (send arrow, Select capsule).
    static let primaryFill = dyn((0.10, 0.10, 0.14, 1), (1, 1, 1, 1))
    static let primaryInk = dyn((1, 1, 1, 1), (0.05, 0.05, 0.09, 1))
    /// The composer field.
    static let fieldFill = dyn((1, 1, 1, 1), (1, 1, 1, 0.07))

    /// Soft card shadow used across the sheet.
    static let cardShadow = dyn((0, 0, 0, 0.10), (0, 0, 0, 0.30))

    /// The canvas bloom for a personality — pastel wash in light mode, a
    /// deep glow in dark mode: mint for the Original, amber for Angel,
    /// ember for Drill Sergeant, violet for Scientist.
    static func bloom(for mode: WhisperEmberCoachMode) -> Color {
        switch mode.resolved {
        case .auto, .regular: return dyn((0.78, 0.95, 0.87, 1), (0.10, 0.23, 0.185, 1))
        case .guardian: return dyn((1.0, 0.90, 0.65, 1), (0.27, 0.21, 0.06, 1))
        case .drillSergeant: return dyn((1.0, 0.83, 0.78, 1), (0.28, 0.09, 0.07, 1))
        case .scientist: return dyn((0.87, 0.82, 1.0, 1), (0.20, 0.15, 0.40, 1))
        }
    }

    /// The sheet's signature backdrop — the adaptive canvas washed with the
    /// personality's glow. The blooms are ALIVE: they drift slowly, and the
    /// whole wash recolours the moment the personality changes.
    struct Backdrop: View {
        var mode: WhisperEmberCoachMode = .regular
        @State private var drift = false

        var body: some View {
            // The blooms live in an OVERLAY, never as layout siblings — a
            // 560pt circle in a ZStack inflates the reported layout size and
            // pushes whole screens wider than sub-Max iPhones (the round-22
            // bug class). Overlays can never affect layout sizing; the Color
            // canvas alone decides this backdrop's size.
            WhisperEmberSheetTheme.canvas
                .overlay {
                    ZStack {
                        Circle()
                            .fill(WhisperEmberSheetTheme.bloom(for: mode))
                            .frame(width: 560, height: 560)
                            .blur(radius: 90)
                            .opacity(0.85)
                            .offset(x: drift ? -44 : 38, y: drift ? -310 : -262)
                        Circle()
                            .fill(WhisperEmberSheetTheme.bloom(for: mode))
                            .frame(width: 360, height: 360)
                            .blur(radius: 90)
                            .opacity(0.36)
                            .offset(x: drift ? -152 : -108, y: drift ? 46 : 128)
                        Circle()
                            .fill(WhisperEmberSheetTheme.lavenderGlow)
                            .frame(width: 470, height: 470)
                            .blur(radius: 100)
                            .opacity(0.32)
                            .offset(x: drift ? 172 : 128, y: drift ? 322 : 392)
                    }
                    .allowsHitTesting(false)
                }
                .clipped()
                .animation(.easeInOut(duration: 0.5), value: mode)
                .onAppear {
                    withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                        drift = true
                    }
                }
        }
    }
}
