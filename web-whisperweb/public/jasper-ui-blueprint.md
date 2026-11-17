# Jasper UI blueprint — the REAL code

Generated 2026-08-26 from the Whisper iOS app. Everything below is the exact
production Swift running in Whisper today — not a description of it. Port these
files into the Jasper app and you get the same grammar, the same modals, the
same analysis animations, pixel for pixel.

Companion admin page (shared brain sections, live on both apps within ~5 min):
https://mydailywhisper.com/jasper-brain

---

## Read this first — how to consume

Port in this order (each file only depends on the ones before it):

1. `WhisperEmberCoachMode.swift` — the personality system (tints, prompt grammar).
2. `WhisperEmberPillStyle.swift` — the pill palette, the mint shell, and the sheet
   theme. This is HOW WE PRODUCE MODALS: every Jasper modal is
   `WhisperEmberSheetTheme.Backdrop` (drifting personality blooms over an
   adaptive canvas) + opaque `pillFill` chrome + `card` surfaces, while
   in-meeting/dock surfaces use the dark glass `shell` (see the dock file).
3. `WhisperEmberMascot.swift` — the living mascot (breathing, blinking, acted
   micro-expressions with staged eye transitions).
4. `JasperAnalysisDock.swift` — the auto-analysis dock ("Jasper's read"):
   collapsed mint pill with the mascot peeking → matched-geometry morph into
   the dark glass assistant box, cached lenses, perform chips.
5. `WhisperEmberThinkingSteps.swift` — the ANALYSIS LOADING ANIMATION: the
   scripted reasoning rail (phases advance every 0.95 s, checkmarks chip off).
6. `WhisperEmberRichText.swift` — the REPLY GRAMMAR: the exact block parser
   (headings, `**Heading**` lines, bullets, numbered lists, `---` dividers)
   + inline markdown, and `plainText()` for typewriter surfaces.
7. `JasperGlowKit.swift` — the ember glow kit: `JasperBrand` tokens,
   `JasperGlowStage`, `JasperGlowBox` (the breathing glow card), `EmberGlowIcon`,
   `JasperKicker`, the plan-entrance spring, the link-confirmation ceremony, and
   the paged glow walkthrough (our full-screen modal pattern).

### Dependencies you must provide (tiny stubs)

The files reference a few Whisper internals. Provide these and everything compiles:

```swift
// Haptics — UIKit feedback wrapper.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// AccountStorage — per-account UserDefaults wrapper. Plain UserDefaults works.
enum AccountStorage {
    static func string(forKey key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    static func set(_ value: String, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }
}

// WhisperEmberAutoMood — readiness-based auto personality. Stub to Original,
// or wire your own readiness score (Whisper: >=75 Drill Sergeant, 50-74
// Original, <50 Angel, with an honest reason line).
enum WhisperEmberAutoMood {
    static var resolved: WhisperEmberCoachMode { .regular }
    static var reason: String { "Auto is not wired yet." }
}

// The ONE AI entry point the dock calls. Wire it to your model call; cache by
// (context + focus) hash unless force is true — that cache IS the credit
// guardrail that makes lens flipping free.
final class WhisperEmberService {
    static let shared = WhisperEmberService()
    func quickAnalysis(context: String, focus: String, force: Bool) async -> String {
        // system: your Jasper system prompt + focus; user: context. Return plain text.
        return ""
    }
}

// Used only by WhisperEmberThinkingSteps' light skin. Map to your theme.
enum WhisperTheme {
    static func ink(_ s: ColorScheme) -> Color { s == .dark ? .white : .black }
    static func muted(_ s: ColorScheme) -> Color { .gray }
    static func card(_ s: ColorScheme) -> Color { s == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04) }
    static func hairline(_ s: ColorScheme) -> Color { s == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08) }
}

// Used by JasperGlowCountsGrid (glow kit). Delete the grid or keep this model.
struct JasperResourceSnapshot: Identifiable {
    let id: String; let symbol: String; let count: Int; let title: String
}
```

In `JasperGlowKit.swift`, `JasperBrand` reads a runtime look store
(`JasperLookStore.shared.look("brand")`) so a server-side redesign restyles the
app live. If you do not have that, delete the `colors` property and the `??`
fallbacks become the constants — they ARE the brand values.

### The one required asset

`WhisperEmberGhostBody` — the ghost silhouette template image (846 × 839 px,
white body on transparent, rendered as a template). The eyes are NOT in the
artwork; they are drawn by code over these template-space rectangles:

- left eye:  x 273, y 192, w 101, h 159
- right eye: x 463, y 192, w 100, h 159

Any ghost-shaped template with eye rects measured the same way works — update
`leftEyeRect` / `rightEyeRect` in `WhisperEmberMascot.swift` to match your art.

### The behaviour rules that make it feel right

- The dock NEVER runs AI on appear. Analysis runs on the FIRST TAP only
  (credit guardrail), then replies cache per lens — reopening and flipping
  lenses is free. `Re-run` is the only path that bypasses the cache.
- The collapsed pill is 34 pt tall; the mascot (size 50) peeks from BEHIND via
  `.background(alignment: .top) { face.offset(y: -26) }`. On the open box the
  offset is -24. The mascot always gets `.allowsHitTesting(false)`.
- Entrance: spring(response 0.75, damping 0.68) with 0.4 s delay, rising 120 pt.
  Pill → box morph: matched geometry id `jasperDockHeader`,
  spring(duration 0.45, bounce 0.2). Close: spring(duration 0.36, bounce 0.12).
- Personality is loaded via `WhisperEmberCoachMode.load()` on appear AND
  re-read on every open; app-wide changes broadcast on
  `Notification.Name.whisperEmberModeChanged`.
- Empty context = the honest `emptyText`, never a fake analysis.
- Mount the dock with `.overlay(alignment: .bottom)` on the screen content and
  pad it clear of your bottom chrome.

### A real mount, verbatim (Whisper recruiter pipeline)

```swift
.overlay(alignment: .bottom) {
    if tab == .today {
        JasperAnalysisDock(
            pillLabel: "Jasper's read",
            boxTitle: "Pipeline analysis",
            focus: """
            You are analyzing a recruiter's live pipeline. From the numbers and prospects below, give a tight read: who is HOT (ready or in meetings) and the single best next contact, anything going stale, then ONE concrete next move for this week. Use the actual usernames.
            """,
            buildContext: { recruiterAnalysisContext() },
            emptyText: "No prospects yet — add your first prospect and I'll analyze the pipeline here.",
            actions: [
                JasperDockAction(
                    id: "rank",
                    label: "Rank pipeline",
                    icon: "list.number",
                    kind: .lens("Stack-rank every prospect below from hottest to coldest — one line each: rank, @handle, why they sit there (status + meetings), and the exact next touch. Use only the listed prospects.")
                ),
                JasperDockAction(
                    id: "outreach",
                    label: "Outreach drafts",
                    icon: "text.bubble",
                    kind: .lens("Write 2 short copy-ready outreach DMs for the two prospects most worth contacting right now. Format: @handle — then the message in quotes. Warm, specific to their status, no hard sell, under 40 words each.")
                ),
                JasperDockAction(
                    id: "stale",
                    label: "Stale leads",
                    icon: "clock.arrow.circlepath",
                    kind: .lens("From the pipeline below, name the prospects going STALE (no movement, stuck status) — one line each with the revival move. If nothing is stale, say the pipeline is moving and name the freshest lead.")
                ),
            ]
        )
        .padding(.bottom, 10)
    }
}
```

`buildContext` returns a plain-text snapshot of whatever the screen shows
(numbers + rows, capped in size). Whisper mounts this same dock on profiles
("Jasper's read": Icebreaker + Common ground lenses), the inbox, Communities,
Whisper Studio, Coach Studio (Who needs attention · Check-in drafts +
an "Automate plans" perform chip), Creator Studio (Post ideas · Growth move),
and client health. In the Jasper app, mount it on workout detail, nutrition
day, sleep trends, and recovery with your own lenses ("Form check",
"Next session", "Trend read").

---

## 1) `WhisperEmberCoachMode.swift` — the personality system (verbatim)

The five modes (Auto resolves to a real one), the EXACT accent hexes, the
signature expressions, and the MODE grammar line appended to every prompt.

```swift
import SwiftUI

/// User-selectable coaching tone for Whisper's full-screen Jasper assistant.
/// Restyled for Whisper's black & white aesthetic: the default "Original" mode
/// is monochrome (greyscale ghost), while the three character modes keep their
/// signature signal colours so the personality reads at a glance.
enum WhisperEmberCoachMode: String, CaseIterable, Identifiable {
    case auto
    case regular
    case guardian
    case drillSergeant = "drill_sergeant"
    case scientist

    var id: String { rawValue }

    /// The concrete ghost this selection renders as. `.auto` resolves to a
    /// real personality via the cached readiness read (never `.auto` back).
    var resolved: WhisperEmberCoachMode {
        self == .auto ? WhisperEmberAutoMood.resolved : self
    }

    var isAuto: Bool { self == .auto }

    static let storageKey = "whisper_ember_coach_mode"

    static func load() -> WhisperEmberCoachMode {
        guard let raw = AccountStorage.string(forKey: storageKey) else { return .regular }
        switch raw {
        case "comforting", "comfort": return .guardian
        case "angry", "drill", "drillSergeant": return .drillSergeant
        default: return WhisperEmberCoachMode(rawValue: raw) ?? .regular
        }
    }

    func save() {
        AccountStorage.set(rawValue, forKey: Self.storageKey)
        // Every Jasper surface (chat, meeting pill, widgets) re-reads the
        // saved mode when this fires — personality switches apply app-wide.
        NotificationCenter.default.post(name: .whisperEmberModeChanged, object: nil)
    }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .regular: return "The Original"
        case .guardian: return "Angel"
        case .drillSergeant: return "Drill Sergeant"
        case .scientist: return "Scientist"
        }
    }

    var shortTitle: String {
        switch self {
        case .auto: return "Auto"
        case .regular: return "Original"
        case .guardian: return "Angel"
        case .drillSergeant: return "Drill"
        case .scientist: return "Science"
        }
    }

    var icon: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .regular: return "sparkles"
        case .guardian: return "shield.lefthalf.filled"
        case .drillSergeant: return "flame.fill"
        case .scientist: return "atom"
        }
    }

    var selectorTagline: String {
        switch self {
        case .auto: return "Jasper picks from today's readiness"
        case .regular: return "Balanced everyday coach"
        case .guardian: return "Protective, recovery-first support"
        case .drillSergeant: return "Tough-love accountability"
        case .scientist: return "Deep data + physiology lens"
        }
    }

    /// Longer copy for the full-screen personality stage (native Jasper
    /// picker) — reads under the big title while the ghost glows centre-stage.
    var selectorDescription: String {
        switch self {
        case .auto:
            return "Jasper reads today's readiness and picks the right coach for you. " + WhisperEmberAutoMood.reason
        case .regular:
            return "The everyday Jasper — balanced, clever, and honest with your numbers. Warm when you need it, direct when it matters."
        case .guardian:
            return "Protective and calm. Angel lowers the pressure, validates your effort, and always leads with recovery-first advice."
        case .drillSergeant:
            return "Zero excuses. The Drill Sergeant brings tough-love intensity and holds you accountable to every single rep."
        case .scientist:
            return "Data-first explanations. The Scientist reasons through the physiology, trends, and mechanisms behind every recommendation."
        }
    }

    // MARK: - Palette
    //
    // "Regular" stays monochrome to honour Whisper's black & white look; the
    // character modes carry a single signal hue used only on the living ghost
    // and its glow (never as a page background).

    var accent: Color {
        switch self {
        case .auto: return resolved.accent
        case .regular: return Color(red: 0.76, green: 0.99, blue: 0.90)   // THE signature mint #C2FCE6 (jasper-plan.md definitive)
        case .guardian: return Color(red: 1.00, green: 0.78, blue: 0.26)  // #FFC742
        case .drillSergeant: return Color(red: 0.96, green: 0.20, blue: 0.16)  // #F53329
        case .scientist: return Color(red: 0.58, green: 0.38, blue: 1.00)  // #9461FF
        }
    }

    var deepAccent: Color {
        switch self {
        case .auto: return resolved.deepAccent
        case .regular: return Color(red: 0.58, green: 0.82, blue: 0.72)   // shadow edge #94D1B8 (jasper-plan.md definitive)
        case .guardian: return Color(red: 0.86, green: 0.55, blue: 0.05)  // #DB8C0D
        case .drillSergeant: return Color(red: 0.64, green: 0.05, blue: 0.04)  // #A30D0A
        case .scientist: return Color(red: 0.32, green: 0.17, blue: 0.72)  // #522BB8
        }
    }

    var softAccent: Color {
        switch self {
        case .auto: return resolved.softAccent
        case .regular: return Color(red: 0.93, green: 1.00, blue: 0.96)   // top sheen #EDFFF5 (jasper-plan.md definitive)
        case .guardian: return Color(red: 1.00, green: 0.92, blue: 0.56)  // #FFEB8F
        case .drillSergeant: return Color(red: 1.00, green: 0.52, blue: 0.42)  // #FF856B
        case .scientist: return Color(red: 0.84, green: 0.72, blue: 1.00)  // #D6B8FF
        }
    }

    var gradient: Gradient {
        Gradient(colors: [softAccent, accent, deepAccent, softAccent])
    }

    var signatureExpression: WhisperEmberMascotExpression {
        switch self {
        case .auto: return resolved.signatureExpression
        case .regular: return .attentive
        case .guardian: return .happy
        case .drillSergeant: return .determined
        case .scientist: return .thinking
        }
    }

    var next: WhisperEmberCoachMode {
        switch self {
        case .auto: return .regular
        case .regular: return .guardian
        case .guardian: return .drillSergeant
        case .drillSergeant: return .scientist
        case .scientist: return .auto
        }
    }

    /// Compact tone instruction passed to the shared brain so replies match the
    /// chosen personality. Appended to `healthContext` for the turn.
    var promptInstruction: String {
        switch self {
        case .auto:
            return resolved.promptInstruction
                + "\n(Auto personality is on: Jasper chose this coach from live readiness — \(WhisperEmberAutoMood.reason))"
        case .regular:
            return "Mode: Original. Be concise, clever, data-grounded, and balanced. Normal Jasper warmth with direct next steps."
        case .guardian:
            return "Mode: Angel. Lead with protection and reassurance, reduce pressure, validate the user's effort, and give calm recovery-first next steps. Avoid harsh phrasing."
        case .drillSergeant:
            return "Mode: Drill Sergeant. Use tough-love intensity like a demanding coach: blunt, urgent, high-accountability, and energizing. Never insult the user, shame their body, or be abusive; channel the intensity into action."
        case .scientist:
            return "Mode: Scientist. Be precise, evidence-informed, and mechanism-aware. Explain the physiology and trend logic behind recommendations, quantify when useful, and keep the answer practical rather than academic."
        }
    }
}

extension Notification.Name {
    /// Posted whenever the saved Jasper personality changes — every surface
    /// (chat, meeting pill, modals) re-reads `WhisperEmberCoachMode.load()`.
    static let whisperEmberModeChanged = Notification.Name("whisperEmberModeChanged")
}
```

## 2) `WhisperEmberPillStyle.swift` — the pill shell, palette, and the sheet theme (verbatim)

The mint shell every pill wears, the personality-adaptive palette, and `WhisperEmberSheetTheme` + its `Backdrop` — the exact way Jasper modals are dressed: an adaptive canvas washed with drifting personality blooms, opaque pill chrome, soft card shadows.

```swift
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

    var body: some View {
        ZStack {
            shape.fill(WhisperEmberPillPalette.fill(for: mode))
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.6), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            shape.strokeBorder(
                WhisperEmberPillPalette.rim(for: mode).opacity(compact ? 0.85 : 0.95),
                lineWidth: 1.5
            )
        }
        .compositingGroup()
        .shadow(
            color: WhisperEmberPillPalette.glow(for: mode).opacity(compact ? 0.22 : 0.34),
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
```

## 3) `WhisperEmberMascot.swift` — the living mascot (verbatim)

Breathing, floating, pulsing glow, randomized blinking, and ACTED expression transitions (staged eye moves, never crossfades). Needs the `WhisperEmberGhostBody` template asset described above.

```swift
import SwiftUI

nonisolated enum WhisperEmberMascotExpression: String, Sendable {
    case calm
    case attentive
    case happy
    case delighted
    case thinking
    case lookingDown
    case focused
    case curious
    case skeptical
    case concerned
    case determined
    case angry
}

/// Optional costume for the mascot — swaps only the colours; every breathing,
/// blinking, and expression animation stays identical.
struct WhisperEmberMascotPalette: Equatable {
    let soft: Color
    let mid: Color
    let deep: Color

    /// The Book of Whisper's Law robes — aged gold to match the tome.
    static let ancientGold = WhisperEmberMascotPalette(
        soft: Color(red: 0.97, green: 0.91, blue: 0.75),
        mid: Color(red: 0.85, green: 0.71, blue: 0.37),
        deep: Color(red: 0.54, green: 0.39, blue: 0.13)
    )
}

/// The living Jasper ghost mascot for Whisper. Renders the canonical ghost
/// silhouette from a template image, then layers SwiftUI breathing, floating,
/// pulsing glow, blinking, and acted micro-expressions on top. Coloured by the
/// active coach mode (monochrome for the default Original tone).
struct WhisperEmberMascot: View {
    var size: CGFloat = 120
    var isActive: Bool = false
    var showsEyes: Bool = true
    var expression: WhisperEmberMascotExpression = .calm
    var coachMode: WhisperEmberCoachMode = .regular
    var cyclesExpressions: Bool = false
    var palette: WhisperEmberMascotPalette? = nil

    @State private var breathe: Bool = false
    @State private var blink: Bool = false
    @State private var glowPulse: Bool = false
    @State private var floatY: CGFloat = 0
    @State private var expressionPhase: Int = 0
    @State private var renderedExpression: WhisperEmberMascotExpression = .calm
    @State private var eyeTransitionStage: EyeTransitionStage = .settled
    @State private var expressionTransitionToken: Int = 0
    @State private var blinkTimer: Timer?
    @State private var expressionTimer: Timer?
    @State private var suppressBlinkUntil: Date = .distantPast

    private let sourceWidth: CGFloat = 846
    private let sourceHeight: CGFloat = 839
    private let leftEyeRect: CGRect = CGRect(x: 273, y: 192, width: 101, height: 159)
    private let rightEyeRect: CGRect = CGRect(x: 463, y: 192, width: 100, height: 159)

    private var ghostHeight: CGFloat { size * sourceHeight / sourceWidth }
    private var scale: CGFloat { size / sourceWidth }

    private var softColor: Color { palette?.soft ?? coachMode.softAccent }
    private var midColor: Color { palette?.mid ?? coachMode.accent }
    private var deepColor: Color { palette?.deep ?? coachMode.deepAccent }
    private var glowColor: Color { palette?.mid ?? coachMode.accent }

    private var bodyFill: LinearGradient {
        LinearGradient(colors: [softColor, midColor, deepColor], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var targetExpression: WhisperEmberMascotExpression {
        guard cyclesExpressions, expression != .lookingDown else { return expression }
        return expressionCyclePhases[expressionPhase % expressionCyclePhases.count]
    }

    private var displayedExpression: WhisperEmberMascotExpression { renderedExpression }

    private var expressionCyclePhases: [WhisperEmberMascotExpression] {
        switch coachMode.resolved {
        case .auto, .regular:
            return [expression, .attentive, expression, .happy, expression, .curious, expression, .thinking]
        case .guardian:
            return [.happy, .delighted, expression, .concerned, .happy, .curious, expression]
        case .drillSergeant:
            return [.focused, .determined, .focused, .skeptical, .determined, .attentive]
        case .scientist:
            return [.thinking, .attentive, .skeptical, expression, .curious, .thinking, .focused]
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                glowLayer
                ghostArtwork
                    .frame(width: size, height: ghostHeight)
                    .scaleEffect(x: breathe ? 1.018 : 0.988, y: breathe ? 1.024 : 0.986, anchor: .center)
                    .offset(y: floatY)
            }
            .frame(width: size, height: ghostHeight)
        }
        .frame(width: size, height: ghostHeight, alignment: .bottom)
        .accessibilityHidden(true)
        .onAppear {
            renderedExpression = targetExpression
            startAnimating()
        }
        .onDisappear {
            blinkTimer?.invalidate(); blinkTimer = nil
            expressionTimer?.invalidate(); expressionTimer = nil
        }
        .onChange(of: isActive) { _, _ in restartGlow() }
        .onChange(of: targetExpression) { _, newValue in transitionExpression(to: newValue) }
        .onChange(of: coachMode) { _, _ in
            expressionPhase = 0
            transitionExpression(to: targetExpression)
            restartGlow()
            scheduleExpressionCycle()
        }
    }

    private var glowLayer: some View {
        ZStack {
            Image("WhisperEmberGhostBody")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(glowColor.opacity(isActive ? 0.55 : 0.34))
                .frame(width: size, height: ghostHeight)
                .blur(radius: size * (isActive ? 0.24 : 0.18))
                .scaleEffect(glowPulse ? 1.18 : 1.02)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [glowColor.opacity(isActive ? 0.36 : 0.22), glowColor.opacity(0.10), .clear],
                        center: .center,
                        startRadius: size * 0.20,
                        endRadius: size * (isActive ? 1.05 : 0.88)
                    )
                )
                .frame(width: size * 1.9, height: size * 1.9)
                .blur(radius: size * 0.15)
                .scaleEffect(glowPulse ? 1.08 : 0.94)
        }
        .opacity(breathe ? 1 : 0.84)
        .allowsHitTesting(false)
    }

    private var ghostArtwork: some View {
        ZStack(alignment: .topLeading) {
            Image("WhisperEmberGhostBody")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(bodyFill)
                .frame(width: size, height: ghostHeight)
                .shadow(color: glowColor.opacity(isActive ? 0.50 : 0.34), radius: size * 0.14, y: size * 0.04)
                .overlay {
                    Image("WhisperEmberGhostBody")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(
                            RadialGradient(
                                colors: [Color.white.opacity(0.32), Color.clear],
                                center: UnitPoint(x: 0.38, y: 0.20),
                                startRadius: 1,
                                endRadius: size * 0.62
                            )
                        )
                }

            if showsEyes {
                expressiveEye(rect: leftEyeRect, side: .left)
                expressiveEye(rect: rightEyeRect, side: .right)
            }
        }
        .compositingGroup()
    }

    private enum EyeSide { case left, right }

    private enum EyeShapeStyle: Equatable { case exactMask, happySmile, sternGlare }

    private struct EyePose {
        let scaleX: CGFloat
        let scaleY: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
        let rotation: Double
        let shapeStyle: EyeShapeStyle
        let shapeWidth: CGFloat
        let shapeHeight: CGFloat
        let shapeYOffset: CGFloat

        init(scaleX: CGFloat = 1, scaleY: CGFloat = 1, offsetX: CGFloat = 0, offsetY: CGFloat = 0,
             rotation: Double = 0, shapeStyle: EyeShapeStyle = .exactMask, shapeWidth: CGFloat = 1,
             shapeHeight: CGFloat = 1, shapeYOffset: CGFloat = 0) {
            self.scaleX = scaleX; self.scaleY = scaleY; self.offsetX = offsetX; self.offsetY = offsetY
            self.rotation = rotation; self.shapeStyle = shapeStyle; self.shapeWidth = shapeWidth
            self.shapeHeight = shapeHeight; self.shapeYOffset = shapeYOffset
        }
    }

    private struct EyeExpressionProfile {
        let left: EyePose
        let right: EyePose
        static func symmetric(_ pose: EyePose) -> EyeExpressionProfile { EyeExpressionProfile(left: pose, right: pose) }
        func pose(for side: EyeSide) -> EyePose { side == .left ? left : right }
    }

    private enum EyeTransitionStage: Equatable {
        case settled, softBlink, smileLift, curiousLeftClosing, skepticalRightClosing, focusNarrowing, attentiveOpening
    }

    private func eyeProfile(for expression: WhisperEmberMascotExpression) -> EyeExpressionProfile {
        switch expression {
        case .calm:
            return .symmetric(EyePose())
        case .attentive:
            return .symmetric(EyePose(scaleX: 1.04, scaleY: 1.12, offsetY: -4))
        case .happy:
            return EyeExpressionProfile(
                left: EyePose(scaleX: 1.03, scaleY: 0.98, offsetX: -3, offsetY: -2, shapeStyle: .happySmile, shapeWidth: 1.04, shapeHeight: 1.0),
                right: EyePose(scaleX: 1.03, scaleY: 0.98, offsetX: 3, offsetY: -2, shapeStyle: .happySmile, shapeWidth: 1.04, shapeHeight: 1.0)
            )
        case .delighted:
            return EyeExpressionProfile(
                left: EyePose(scaleX: 1.13, scaleY: 0.88, offsetX: -7, offsetY: -7, rotation: -6, shapeStyle: .happySmile, shapeWidth: 1.10, shapeHeight: 0.98, shapeYOffset: -0.01),
                right: EyePose(scaleX: 1.13, scaleY: 0.88, offsetX: 7, offsetY: -7, rotation: 6, shapeStyle: .happySmile, shapeWidth: 1.10, shapeHeight: 0.98, shapeYOffset: -0.01)
            )
        case .thinking:
            return .symmetric(EyePose(scaleX: 0.80, scaleY: 1.03, offsetX: 24, offsetY: 0, rotation: -1))
        case .lookingDown:
            return .symmetric(EyePose(scaleX: 0.96, scaleY: 0.86, offsetY: 16))
        case .focused:
            return EyeExpressionProfile(
                left: EyePose(scaleX: 0.88, scaleY: 0.68, offsetX: 9, offsetY: 3, rotation: -9),
                right: EyePose(scaleX: 0.88, scaleY: 0.68, offsetX: -9, offsetY: 3, rotation: 9)
            )
        case .curious:
            return EyeExpressionProfile(
                left: EyePose(scaleX: 0.84, scaleY: 0.72, offsetX: -5, offsetY: 7, rotation: 8),
                right: EyePose(scaleX: 1.12, scaleY: 1.10, offsetX: 12, offsetY: -3, rotation: -5)
            )
        case .skeptical:
            return EyeExpressionProfile(
                left: EyePose(scaleX: 1.08, scaleY: 1.02, offsetX: -7, offsetY: -2, rotation: 5),
                right: EyePose(scaleX: 0.78, scaleY: 0.56, offsetX: 4, offsetY: 8, rotation: -8)
            )
        case .concerned:
            return EyeExpressionProfile(
                left: EyePose(scaleX: 0.96, scaleY: 0.78, offsetX: 6, offsetY: 5, rotation: 7),
                right: EyePose(scaleX: 0.96, scaleY: 0.78, offsetX: -6, offsetY: 5, rotation: -7)
            )
        case .determined:
            return EyeExpressionProfile(
                left: EyePose(scaleX: 1.0, scaleY: 1.0, offsetX: 4, offsetY: 1, rotation: 6, shapeStyle: .sternGlare, shapeWidth: 1.46, shapeHeight: 1.44),
                right: EyePose(scaleX: 1.0, scaleY: 1.0, offsetX: -4, offsetY: 1, rotation: -6, shapeStyle: .sternGlare, shapeWidth: 1.46, shapeHeight: 1.44)
            )
        case .angry:
            return EyeExpressionProfile(
                left: EyePose(scaleX: 1.04, scaleY: 1.04, offsetX: 5, offsetY: 2, rotation: 9, shapeStyle: .sternGlare, shapeWidth: 1.56, shapeHeight: 1.54),
                right: EyePose(scaleX: 1.04, scaleY: 1.04, offsetX: -5, offsetY: 2, rotation: -9, shapeStyle: .sternGlare, shapeWidth: 1.56, shapeHeight: 1.54)
            )
        }
    }

    private func stagedEyeScaleY(for side: EyeSide) -> CGFloat? {
        switch eyeTransitionStage {
        case .settled: return nil
        case .softBlink: return 0.22
        case .smileLift: return 0.62
        case .curiousLeftClosing: return side == .left ? 0.16 : 1.0
        case .skepticalRightClosing: return side == .right ? 0.16 : 1.0
        case .focusNarrowing: return 0.42
        case .attentiveOpening: return 1.16
        }
    }

    @ViewBuilder
    private func expressiveEye(rect: CGRect, side: EyeSide) -> some View {
        let pose = eyeProfile(for: displayedExpression).pose(for: side)
        let canBlink = Date() >= suppressBlinkUntil && eyeTransitionStage == .settled
        let isBlinking = blink && canBlink
        let isLidBlink = isBlinking || eyeTransitionStage == .softBlink
        let yScale = isLidBlink ? 0.075 : (stagedEyeScaleY(for: side) ?? pose.scaleY)
        let xScale = isLidBlink ? pose.scaleX * 1.06 : pose.scaleX
        let blinkSlant: Double = isLidBlink ? (side == .left ? 7 : -7) : 0
        let xOffset = pose.offsetX * scale
        let yOffset = pose.offsetY * scale
        let shapeStyle = isLidBlink ? EyeShapeStyle.exactMask : pose.shapeStyle

        ZStack {
            WhisperEmberStandardEyeShape().fill(Color.black).opacity(shapeStyle == .exactMask ? 1 : 0)
            WhisperEmberHappyEyeShape().fill(Color.black).opacity(shapeStyle == .happySmile ? 1 : 0)
            WhisperEmberAngryEyeShape(isLeft: side == .left).fill(Color.black).opacity(shapeStyle == .sternGlare ? 1 : 0)
        }
        .frame(width: rect.width * scale * pose.shapeWidth, height: rect.height * scale * pose.shapeHeight)
        .offset(y: rect.height * scale * pose.shapeYOffset)
        .transaction { $0.disablesAnimations = true }
        .scaleEffect(x: xScale, y: yScale, anchor: .center)
        .rotationEffect(.degrees(pose.rotation + blinkSlant))
        .offset(x: xOffset, y: yOffset)
        .position(x: rect.midX * scale, y: rect.midY * scale)
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private func startAnimating() {
        withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { breathe = true }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { floatY = -size * 0.035 }
        restartGlow()
        scheduleBlink()
        scheduleExpressionCycle()
    }

    private func restartGlow() {
        glowPulse = false
        withAnimation(.easeInOut(duration: isActive ? 1.05 : 2.45).repeatForever(autoreverses: true)) {
            glowPulse = true
        }
    }

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 2.8...5.2), repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.10)) { blink = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                    withAnimation(.easeInOut(duration: 0.12)) { blink = false }
                    scheduleBlink()
                }
            }
        }
    }

    private func scheduleExpressionCycle() {
        expressionTimer?.invalidate()
        guard cyclesExpressions else { expressionPhase = 0; return }
        expressionTimer = Timer.scheduledTimer(withTimeInterval: 3.65, repeats: true) { _ in
            Task { @MainActor in transitionToNextExpression() }
        }
    }

    private func transitionToNextExpression() {
        withAnimation(.easeInOut(duration: 0.18)) { expressionPhase &+= 1 }
    }

    private func transitionExpression(to newExpression: WhisperEmberMascotExpression) {
        guard renderedExpression != newExpression else { return }
        expressionTransitionToken &+= 1
        let token = expressionTransitionToken
        suppressBlinkUntil = Date().addingTimeInterval(0.95)
        blink = false

        if isSmileFamily(renderedExpression) && !isSmileFamily(newExpression) {
            applyStage(.softBlink, token: token, after: 0, animation: .easeInOut(duration: 0.12))
            settleExpression(to: newExpression, token: token, after: 0.13, animation: .spring(response: 0.38, dampingFraction: 0.92))
            return
        }

        switch newExpression {
        case .calm:
            settleExpression(to: .calm, token: token, after: 0, animation: .spring(response: 0.46, dampingFraction: 0.90))
        case .attentive:
            applyStage(.attentiveOpening, token: token, after: 0, animation: .easeOut(duration: 0.14))
            settleExpression(to: .attentive, token: token, after: 0.14, animation: .spring(response: 0.42, dampingFraction: 0.86))
        case .happy, .delighted:
            applyStage(.smileLift, token: token, after: 0, animation: .easeInOut(duration: 0.16))
            settleExpression(to: newExpression, token: token, after: 0.16, animation: .spring(response: 0.46, dampingFraction: 0.82))
        case .thinking:
            settleExpression(to: .attentive, token: token, after: 0, animation: .easeOut(duration: 0.12))
            settleExpression(to: .thinking, token: token, after: 0.15, animation: .spring(response: 0.44, dampingFraction: 0.88))
        case .lookingDown:
            settleExpression(to: .lookingDown, token: token, after: 0, animation: .spring(response: 0.44, dampingFraction: 0.88))
        case .focused, .concerned, .determined:
            applyStage(.focusNarrowing, token: token, after: 0, animation: .easeInOut(duration: 0.18))
            settleExpression(to: newExpression, token: token, after: 0.18, animation: .spring(response: 0.48, dampingFraction: 0.88))
        case .curious:
            settleExpression(to: .calm, token: token, after: 0, animation: .easeOut(duration: 0.10))
            applyStage(.curiousLeftClosing, token: token, after: 0.05, animation: .easeInOut(duration: 0.24))
            settleExpression(to: .curious, token: token, after: 0.29, animation: .spring(response: 0.46, dampingFraction: 0.90))
        case .skeptical:
            settleExpression(to: .calm, token: token, after: 0, animation: .easeOut(duration: 0.10))
            applyStage(.skepticalRightClosing, token: token, after: 0.05, animation: .easeInOut(duration: 0.22))
            settleExpression(to: .skeptical, token: token, after: 0.27, animation: .spring(response: 0.46, dampingFraction: 0.90))
        case .angry:
            settleExpression(to: .determined, token: token, after: 0, animation: .easeOut(duration: 0.14))
            applyStage(.focusNarrowing, token: token, after: 0.08, animation: .easeInOut(duration: 0.22))
            settleExpression(to: .angry, token: token, after: 0.30, animation: .spring(response: 0.52, dampingFraction: 0.90))
        }
    }

    private func isSmileFamily(_ expression: WhisperEmberMascotExpression) -> Bool {
        expression == .happy || expression == .delighted
    }

    private func applyStage(_ stage: EyeTransitionStage, token: Int, after delay: TimeInterval, animation: Animation) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard token == expressionTransitionToken else { return }
            withAnimation(animation) { eyeTransitionStage = stage }
        }
    }

    private func settleExpression(to newExpression: WhisperEmberMascotExpression, token: Int, after delay: TimeInterval, animation: Animation) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard token == expressionTransitionToken else { return }
            withAnimation(animation) {
                renderedExpression = newExpression
                eyeTransitionStage = .settled
            }
        }
    }
}

private struct WhisperEmberStandardEyeShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path { Path(ellipseIn: rect) }
}

private struct WhisperEmberHappyEyeShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let kappa: CGFloat = 0.5522847498
        let bottomY = rect.minY + h * 0.86
        let smileApexY = rect.minY + h * 0.60
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                      control1: CGPoint(x: rect.midX + w * 0.5 * kappa, y: rect.minY),
                      control2: CGPoint(x: rect.maxX, y: rect.midY - h * 0.5 * kappa))
        path.addCurve(to: CGPoint(x: rect.maxX, y: bottomY),
                      control1: CGPoint(x: rect.maxX, y: rect.midY + h * 0.16),
                      control2: CGPoint(x: rect.maxX, y: bottomY - h * 0.10))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: bottomY), control: CGPoint(x: rect.midX, y: smileApexY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                      control1: CGPoint(x: rect.minX, y: bottomY - h * 0.10),
                      control2: CGPoint(x: rect.minX, y: rect.midY + h * 0.16))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.midY - h * 0.5 * kappa),
                      control2: CGPoint(x: rect.midX - w * 0.5 * kappa, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct WhisperEmberAngryEyeShape: Shape {
    let isLeft: Bool
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        if isLeft {
            let outerTop = CGPoint(x: rect.minX + w * 0.06, y: rect.minY + h * 0.22)
            let innerTop = CGPoint(x: rect.maxX - w * 0.05, y: rect.minY + h * 0.58)
            let bottomCenter = CGPoint(x: rect.midX + w * 0.04, y: rect.maxY - h * 0.06)
            path.move(to: outerTop)
            path.addQuadCurve(to: innerTop, control: CGPoint(x: rect.midX + w * 0.06, y: rect.minY + h * 0.54))
            path.addQuadCurve(to: bottomCenter, control: CGPoint(x: rect.maxX - w * 0.02, y: rect.maxY - h * 0.04))
            path.addQuadCurve(to: outerTop, control: CGPoint(x: rect.minX + w * 0.01, y: rect.maxY - h * 0.02))
        } else {
            let outerTop = CGPoint(x: rect.maxX - w * 0.06, y: rect.minY + h * 0.22)
            let innerTop = CGPoint(x: rect.minX + w * 0.05, y: rect.minY + h * 0.58)
            let bottomCenter = CGPoint(x: rect.midX - w * 0.04, y: rect.maxY - h * 0.06)
            path.move(to: outerTop)
            path.addQuadCurve(to: innerTop, control: CGPoint(x: rect.midX - w * 0.06, y: rect.minY + h * 0.54))
            path.addQuadCurve(to: bottomCenter, control: CGPoint(x: rect.minX + w * 0.02, y: rect.maxY - h * 0.04))
            path.addQuadCurve(to: outerTop, control: CGPoint(x: rect.maxX - w * 0.01, y: rect.maxY - h * 0.02))
        }
        path.closeSubpath()
        return path
    }
}
```

## 4) `JasperAnalysisDock.swift` — the auto-analysis dock (verbatim)

The collapsed pill, the matched-geometry morph into the dark glass box, the reply card dressing, lens + perform chips, and the tap-to-run cache logic.

```swift
import SwiftUI
import UIKit

/// Optional quick action rendered as a chip in the dock's footer.
/// `.lens` re-runs the analysis through a different instruction (cached per
/// lens, instant to flip back); `.perform` hands control to the host screen
/// (open a wizard, a tool, a sheet…).
struct JasperDockAction: Identifiable {
    enum Kind {
        case lens(String)
        case perform(() -> Void)
    }

    let id: String
    let label: String
    let icon: String
    let kind: Kind

    var isLens: Bool {
        if case .lens = kind { return true }
        return false
    }
}

/// The meeting-style Jasper companion, reusable on any screen: the living
/// mascot peeks from behind the pale personality pill docked at the bottom;
/// tapping floats it upward into the dark glass assistant box (matched
/// geometry — the exact language of the in-meeting Jasper) and runs an
/// automatic analysis of whatever the host screen is showing, right there,
/// without leaving for the full-screen chat.
struct JasperAnalysisDock: View {
    /// Pill text while collapsed (e.g. "Jasper's read").
    var pillLabel: String = "Jasper's read"
    /// Header title once the box is open.
    var boxTitle: String = "Jasper's read"
    /// The brain instruction for THIS surface.
    let focus: String
    /// Live context for the analysis; nil/empty = honest empty state.
    let buildContext: () -> String?
    var emptyText: String = "Nothing to analyze here yet."
    /// Surface-tailored quick actions — alternate analysis lenses and/or
    /// host-provided tools, rendered as chips in the box footer.
    var actions: [JasperDockAction] = []

    private static let defaultLensID = "read"

    @State private var open = false
    @State private var peekedIn = false
    @State private var busy = false
    @State private var replies: [String: String] = [:]
    @State private var activeLens: String = JasperAnalysisDock.defaultLensID
    @State private var mode: WhisperEmberCoachMode = WhisperEmberCoachMode.load()
    @Namespace private var ns

    private var reply: String? { replies[activeLens] }

    /// The instruction for a given lens id — the default lens uses `focus`.
    private func focusText(for lensID: String) -> String {
        guard lensID != Self.defaultLensID else { return focus }
        for action in actions {
            if action.id == lensID, case .lens(let text) = action.kind { return text }
        }
        return focus
    }

    var body: some View {
        Group {
            if open {
                box
                    .transition(.scale(scale: 0.82, anchor: .bottom).combined(with: .opacity))
            } else {
                pill
            }
        }
        .onAppear {
            mode = WhisperEmberCoachMode.load()
            guard !peekedIn else { return }
            withAnimation(.spring(response: 0.75, dampingFraction: 0.68).delay(0.4)) {
                peekedIn = true
            }
        }
    }

    // MARK: - Collapsed pill (mascot peeking from behind)

    private var pill: some View {
        Button {
            Haptics.tap()
            mode = WhisperEmberCoachMode.load()
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) { open = true }
            if reply == nil, !busy {
                Task { await run(force: false) }
            }
        } label: {
            Text(busy ? "Thinking…" : pillLabel)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(WhisperEmberPillPalette.ink(for: mode))
                .lineLimit(1)
                .padding(.horizontal, 20)
                .frame(height: 34)
                .background { WhisperEmberMintShell(shape: Capsule(), mode: mode) }
                .background(alignment: .top) { face.offset(y: -26) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pillLabel)
        .matchedGeometryEffect(id: "jasperDockHeader", in: ns, isSource: !open)
        .opacity(peekedIn ? 1 : 0)
        .offset(y: peekedIn ? 0 : 120)
    }

    // MARK: - Expanded box (dark glass, meeting language)

    private var box: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(boxTitle)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(WhisperEmberPillPalette.ink(for: mode))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    Haptics.tap()
                    withAnimation(.spring(duration: 0.36, bounce: 0.12)) { open = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WhisperEmberPillPalette.ink(for: mode).opacity(0.55))
                        .frame(width: 22, height: 22)
                        .background(WhisperEmberPillPalette.ink(for: mode).opacity(0.08), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Jasper")
            }
            .padding(.leading, 16)
            .padding(.trailing, 7)
            .frame(height: 36)
            .background { WhisperEmberMintShell(shape: Capsule(), mode: mode) }
            .matchedGeometryEffect(id: "jasperDockHeader", in: ns, isSource: open)
            .padding(.horizontal, 10)
            .padding(.top, 10)

            ViewThatFits(in: .vertical) {
                contentBlock
                ScrollView(showsIndicators: false) { contentBlock }
            }
            .frame(maxHeight: 280, alignment: .top)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    toolChip(busy ? "Reading…" : "Re-run", icon: "arrow.clockwise") {
                        guard !busy else { return }
                        Task { await run(force: true) }
                    }
                    if actions.contains(where: { $0.isLens }) {
                        lensChip(id: Self.defaultLensID, label: "Read", icon: "sparkles")
                    }
                    ForEach(actions) { action in
                        switch action.kind {
                        case .lens:
                            lensChip(id: action.id, label: action.label, icon: action.icon)
                        case .perform(let go):
                            toolChip(action.label, icon: action.icon) {
                                withAnimation(.spring(duration: 0.36, bounce: 0.12)) { open = false }
                                go()
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 10)
        }
        .frame(width: min(UIScreen.main.bounds.width - 24, 380))
        .background { shell(RoundedRectangle(cornerRadius: 24)) }
        .background(alignment: .top) { face.offset(y: -24) }
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if busy {
                WhisperEmberThinkingSteps(
                    coachMode: mode,
                    resolvedLabel: nil,
                    isAnalytical: true,
                    onDark: true,
                    flavor: .meeting,
                    listenState: .hidden
                )
            } else if let reply {
                replyCard(reply)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Dressed exactly like the in-meeting answer: JASPER header with the
    /// personality chip, tinted accent bar, left-aligned styled text.
    private func replyCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(mode.softAccent)
                Text("JASPER")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(mode.softAccent)
                Spacer(minLength: 6)
                Text(mode.shortTitle.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            WhisperEmberRichText(text: text, onDark: true, baseSize: 15)
        }
        .padding(.vertical, 11)
        .padding(.leading, 14)
        .padding(.trailing, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 16))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(mode.accent.opacity(0.7))
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(mode.accent.opacity(0.2), lineWidth: 1)
        }
    }

    /// A lens chip — switches the analysis instruction; highlighted while
    /// active, cached per lens so flipping back is instant.
    private func lensChip(id: String, label: String, icon: String) -> some View {
        let selected = activeLens == id
        return Button {
            Haptics.tap()
            withAnimation(.spring(duration: 0.3)) { activeLens = id }
            if replies[id] == nil, !busy {
                Task { await run(force: false) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? WhisperEmberPillPalette.ink(for: mode) : .white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if selected {
                    Capsule().fill(mode.accent.opacity(0.9))
                } else {
                    Capsule().fill(Color.white.opacity(0.08))
                }
            }
            .overlay {
                Capsule().strokeBorder(
                    selected ? mode.accent : Color.white.opacity(0.12), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toolChip(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared chrome

    /// The living mascot that peeks over the pill / box top edge.
    private var face: some View {
        ZStack {
            if busy {
                // Personality-tinted working glow behind the mascot — the
                // meeting halo is private to the room, so the dock draws its
                // own pulse in the same language.
                Circle()
                    .fill(mode.accent)
                    .frame(width: 44, height: 44)
                    .blur(radius: 14)
                    .phaseAnimator([0.35, 0.8]) { view, glow in
                        view.opacity(glow)
                    } animation: { _ in
                        .easeInOut(duration: 0.9)
                    }
            }
            WhisperEmberMascot(
                size: 50,
                isActive: busy,
                expression: busy ? .thinking : (reply != nil ? mode.signatureExpression : .calm),
                coachMode: mode,
                cyclesExpressions: !busy && reply == nil
            )
        }
        .phaseAnimator([false, true]) { view, phase in
            view.offset(y: phase ? 2 : -2)
        } animation: { _ in
            .easeInOut(duration: 1.7)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The in-meeting dark glass shell, personality tinted.
    private func shell(_ shape: some InsettableShape) -> some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.black.opacity(0.45))
            shape.fill(
                LinearGradient(
                    colors: [mode.accent.opacity(0.20), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.strokeBorder(mode.accent.opacity(0.32), lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: mode.accent.opacity(0.25), radius: 16, y: 5)
        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
    }

    // MARK: - The analysis itself

    private func run(force: Bool) async {
        guard !busy else { return }
        let lens = activeLens
        withAnimation(.easeInOut(duration: 0.2)) { busy = true }
        defer { withAnimation(.spring(duration: 0.35)) { busy = false } }
        let context = (buildContext() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty else {
            replies[lens] = emptyText
            return
        }
        let text = await WhisperEmberService.shared.quickAnalysis(
            context: context, focus: focusText(for: lens), force: force)
        replies[lens] = text.isEmpty ? emptyText : text
    }
}
```

## 5) `WhisperEmberThinkingSteps.swift` — the analysis loading animation (verbatim)

The scripted reasoning rail: phases advance every 0.95 s, finished phases chip off with checkmarks, the tiny mascot thinks alongside. Two skins — light chat and dark glass.

```swift
import SwiftUI

/// A live, animated reasoning rail shown while Jasper works. It scripts
/// through honest, plain-language phases (reading your data → writing code →
/// running it → drawing the chart) so the wait feels like genuine work, and
/// each finished phase chips off with a checkmark.
///
/// Labels are generic and never fabricate numbers — the real code, output, and
/// charts live behind the summary chip's detail sheet.
///
/// Two skins: the standard Whisper theme for the chat sheet, and `onDark` —
/// white on glass with the personality accent — for the in-meeting Jasper box.
///
/// In meetings this is the ONE working box: when a voice question is being
/// captured it opens with a live "Listening" phase that checks off the moment
/// Jasper starts thinking, so listening → thinking reads as one continuous run.
struct WhisperEmberThinkingSteps: View {
    @Environment(\.colorScheme) private var colorScheme

    /// The active personality (colours the little mascot on the rail).
    var coachMode: WhisperEmberCoachMode = .regular
    /// Once `/interpret` resolves, its real intent label caps the rail so the
    /// last row reads as the actual analysis Jasper ran.
    var resolvedLabel: String?
    /// Whether the interpreter actually computed something (drives the phase set).
    var isAnalytical: Bool
    /// White-on-glass skin for dark surfaces (the in-meeting Jasper box).
    var onDark: Bool = false
    /// Which script the rail walks — the chat pipeline or a private
    /// mid-meeting answer.
    var flavor: Flavor = .chat
    /// Voice-capture phase folded into the rail (meetings): `.listening`
    /// holds on a live "Listening" row, `.done` shows it checked, `.hidden`
    /// omits the row entirely (typed questions).
    var listenState: ListenState = .hidden

    nonisolated enum Flavor {
        case chat
        case meeting
    }

    nonisolated enum ListenState: Equatable {
        case hidden, listening, done
    }

    @State private var activeIndex: Int = 0
    @State private var advanceTimer: Timer?

    private var phases: [Phase] {
        switch flavor {
        case .meeting:
            var list: [Phase] = []
            if listenState != .hidden {
                list.append(Phase(icon: "waveform", label: "Listening — just ask"))
            }
            list.append(contentsOf: [
                Phase(icon: "ear", label: "Reading the meeting"),
                Phase(icon: "tray.full", label: "Pulling your Whisper context"),
                Phase(icon: "text.bubble", label: resolvedLabel ?? "Writing your private answer"),
            ])
            return list
        case .chat:
            if isAnalytical {
                return [
                    Phase(icon: "tray.full", label: "Reading your data"),
                    Phase(icon: "chevron.left.forwardslash.chevron.right", label: "Writing the analysis"),
                    Phase(icon: "play.circle", label: "Running it on your numbers"),
                    Phase(icon: "chart.xyaxis.line", label: resolvedLabel ?? "Drawing the chart"),
                ]
            }
            return [
                Phase(icon: "sparkles", label: "Thinking"),
                Phase(icon: "text.bubble", label: "Composing your answer"),
            ]
        }
    }

    private struct Phase {
        let icon: String
        let label: String
    }

    // MARK: - Skin

    private var inkTone: Color { onDark ? .white : WhisperTheme.ink(colorScheme) }
    private var mutedTone: Color { onDark ? Color.white.opacity(0.5) : WhisperTheme.muted(colorScheme) }
    private var cardTone: Color { onDark ? Color.white.opacity(0.07) : WhisperTheme.card(colorScheme) }
    private var hairlineTone: Color { onDark ? Color.white.opacity(0.10) : WhisperTheme.hairline(colorScheme) }
    /// Tint for the active spinner and done checks — the personality accent
    /// pops on dark glass; standard ink on the themed chat surface.
    private var markerTone: Color { onDark ? coachMode.accent : WhisperTheme.ink(colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            WhisperEmberMascot(
                size: 24,
                isActive: true,
                expression: listenState == .listening ? .attentive : .thinking,
                coachMode: coachMode
            )
            .frame(width: 24, height: 26)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(phases.enumerated()), id: \.offset) { idx, phase in
                    row(phase, index: idx, isLast: idx == phases.count - 1)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(cardTone, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(hairlineTone, lineWidth: 1)
            }
            Spacer(minLength: 0)
        }
        .onAppear { startScript() }
        .onDisappear { advanceTimer?.invalidate(); advanceTimer = nil }
        .onChange(of: resolvedLabel) { _, newValue in
            // When the real intent lands, jump the rail to the final phase.
            if newValue != nil { withAnimation(.spring(response: 0.35)) { activeIndex = phases.count - 1 } }
        }
        .onChange(of: listenState) { old, new in
            // Voice capture finished → chip the Listening row and start the
            // thinking phases without remounting the box.
            if old == .listening && new != .listening {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                    activeIndex = max(activeIndex, min(1, phases.count - 1))
                }
                scheduleAdvance()
            }
        }
    }

    private func row(_ phase: Phase, index: Int, isLast: Bool) -> some View {
        let status: Status = index < activeIndex ? .done : (index == activeIndex ? .active : .pending)
        let isListeningRow = index == 0 && listenState == .listening
        return HStack(alignment: .center, spacing: 9) {
            VStack(spacing: 0) {
                glyph(status, listening: isListeningRow)
                    .frame(width: 16, height: 16)
                if !isLast {
                    Rectangle()
                        .fill(inkTone.opacity(0.16))
                        .frame(width: 1.5, height: 14)
                }
            }
            Text(phase.label)
                .font(.caption.weight(status == .active ? .bold : .semibold))
                .foregroundStyle(status == .pending ? mutedTone : inkTone)
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .padding(.bottom, isLast ? 0 : 2)
    }

    private enum Status { case pending, active, done }

    @ViewBuilder
    private func glyph(_ status: Status, listening: Bool) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(markerTone)
                .transition(.scale.combined(with: .opacity))
        case .active:
            if listening {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(markerTone)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(markerTone)
            }
        case .pending:
            Circle()
                .strokeBorder(inkTone.opacity(0.22), lineWidth: 1.5)
                .frame(width: 9, height: 9)
        }
    }

    private func startScript() {
        advanceTimer?.invalidate()
        // Rejoining mid-run (capture ended between renders): start past the
        // already-checked Listening row instead of replaying it.
        activeIndex = listenState == .done ? min(1, phases.count - 1) : 0
        scheduleAdvance()
    }

    /// Advances one phase every beat — but never while the rail is pinned on
    /// a live Listening row (the mic decides when that phase ends).
    private func scheduleAdvance() {
        advanceTimer?.invalidate()
        advanceTimer = Timer.scheduledTimer(withTimeInterval: 0.95, repeats: true) { _ in
            Task { @MainActor in
                guard listenState != .listening else { return }
                guard activeIndex < phases.count - 1 else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { activeIndex += 1 }
            }
        }
    }
}
```

## 6) `WhisperEmberRichText.swift` — the reply grammar (verbatim)

The exact block parser every Jasper answer renders through: `#` headings, whole-line `**bold**` headings, bullets, numbered lists, `---` dividers, inline markdown spans, and `plainText()` for typewriter surfaces.

```swift
import SwiftUI

/// Lightweight rich renderer for Jasper's answers — bold section headings,
/// bullet and numbered lists, dividers, and inline **bold** / *italic*
/// spans. Works on the light assistant sheet and (via `onDark`) on the
/// in-meeting glass box. No external dependencies, never fails: anything
/// unparseable falls back to plain text.
struct WhisperEmberRichText: View {
    let text: String
    var onDark: Bool = false
    var baseSize: CGFloat = 15
    /// Optional explicit ink (the chat sheet passes its pastel ink).
    var inkOverride: Color? = nil

    private var ink: Color {
        inkOverride ?? (onDark ? .white : WhisperEmberSheetTheme.ink)
    }
    private var soft: Color { ink.opacity(onDark ? 0.55 : 0.5) }

    var body: some View {
        let blocks = Self.blocks(from: text)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: RichBlock) -> some View {
        switch block {
        case .heading(let string, let level):
            Text(Self.inline(string))
                .font(.system(
                    size: baseSize + (level == 1 ? 4 : (level == 2 ? 3 : 1.5)),
                    weight: level >= 3 ? .bold : .heavy
                ))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        case .bullet(let string):
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(soft)
                    .frame(width: 5, height: 5)
                    .padding(.top, baseSize * 0.42)
                Text(Self.inline(string))
                    .font(.system(size: baseSize))
                    .foregroundStyle(ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .numbered(let n, let string):
            HStack(alignment: .top, spacing: 8) {
                Text("\(n).")
                    .font(.system(size: baseSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(soft)
                Text(Self.inline(string))
                    .font(.system(size: baseSize))
                    .foregroundStyle(ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .divider:
            Rectangle()
                .fill(ink.opacity(onDark ? 0.14 : 0.08))
                .frame(height: 1)
                .padding(.vertical, 2)
        case .paragraph(let string):
            Text(Self.inline(string))
                .font(.system(size: baseSize))
                .foregroundStyle(ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Parsing

    nonisolated enum RichBlock: Hashable {
        case heading(String, level: Int)
        case bullet(String)
        case numbered(Int, String)
        case paragraph(String)
        case divider
    }

    nonisolated static func blocks(from text: String) -> [RichBlock] {
        var out: [RichBlock] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == "---" || line == "***" || line == "___" {
                out.append(.divider)
                continue
            }
            if line.hasPrefix("#### ") { out.append(.heading(String(line.dropFirst(5)), level: 3)); continue }
            if line.hasPrefix("### ") { out.append(.heading(String(line.dropFirst(4)), level: 3)); continue }
            if line.hasPrefix("## ") { out.append(.heading(String(line.dropFirst(3)), level: 2)); continue }
            if line.hasPrefix("# ") { out.append(.heading(String(line.dropFirst(2)), level: 1)); continue }
            // A whole line wrapped in ** reads as a section heading.
            if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4,
               !line.dropFirst(2).dropLast(2).contains("**") {
                out.append(.heading(String(line.dropFirst(2).dropLast(2)), level: 3))
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ") {
                out.append(.bullet(String(line.dropFirst(2))))
                continue
            }
            if let match = line.range(of: #"^\d{1,2}[\.\)]\s+"#, options: .regularExpression) {
                let numberText = line[..<match.upperBound]
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".) \t"))
                out.append(.numbered(Int(numberText) ?? 1, String(line[match.upperBound...])))
                continue
            }
            out.append(.paragraph(line))
        }
        return out
    }

    /// Inline **bold** / *italic* / `code` spans via Foundation's markdown
    /// parser; falls back to the raw string when parsing fails.
    nonisolated static func inline(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: string, options: options))
            ?? AttributedString(string)
    }

    /// Strips markdown markers for surfaces that type text out plainly
    /// (the streaming typewriter) so raw `**`/`#` never flash on screen.
    nonisolated static func plainText(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "**", with: "")
        for marker in ["#### ", "### ", "## ", "# "] {
            out = out.replacingOccurrences(of: marker, with: "")
        }
        return out
    }
}
```

## 7) `JasperGlowKit.swift` — the ember glow kit + full-screen modals (verbatim)

`JasperBrand` tokens (the published brand hexes and macro accents), `JasperGlowStage`, `JasperGlowBox` with the breathing loading glow, `EmberGlowIcon`, `JasperKicker`, the plan-entrance spring, the link-confirmation ceremony, and the paged glow walkthrough — our full-screen modal pattern.

```swift
import SwiftUI

// MARK: - Brand palette (runtime-first)

/// Jasper's published brand language (GET /v1/catalog → looks.brand, the same
/// language as thejasperapp.com): ink #211C1A canvas, cream #FBF4E4 type, the
/// signature ember gradient #F39057 → #E76F3A, "big numbers in a bold rounded
/// face; section labels small caps with wide tracking." Colors prefer the
/// LIVE look store so a Jasper redesign restyles every branded moment in
/// Whisper automatically.
enum JasperBrand {
    private static var colors: JasperLook? {
        JasperLookStore.shared.look("brand")?.look("colors")
    }

    static var ink: Color { colors?.color("ink") ?? Color(red: 0.129, green: 0.110, blue: 0.102) }
    static var cream: Color { colors?.color("cream") ?? Color(red: 0.984, green: 0.957, blue: 0.894) }
    static var ember: Color { colors?.color("ember") ?? Color(red: 0.953, green: 0.565, blue: 0.341) }
    static var emberDeep: Color { colors?.color("ember_deep") ?? Color(red: 0.906, green: 0.435, blue: 0.227) }

    // WHISPER_PLANS.md §1 — the shared EmberBrand accents.
    /// #3394E0 — fat macro, info accents.
    static let blue = Color(red: 0.20, green: 0.58, blue: 0.88)
    /// #5CDBB8 — protein macro, success/checked.
    static let teal = Color(red: 0.36, green: 0.86, blue: 0.72)
    /// #F2B14D — carbs macro, warnings.
    static let amber = Color(red: 0.95, green: 0.69, blue: 0.30)
    /// #9E6B40 — coach attribution accents.
    static let bronze = Color(red: 0.62, green: 0.42, blue: 0.25)

    /// Canonical macro accents (WHISPER_PLANS.md §4): kcal ember · protein teal ·
    /// carbs amber · fat blue. Never invent macro colors.
    static var macroKcal: Color { ember }
    static var macroProtein: Color { teal }
    static var macroCarbs: Color { amber }
    static var macroFat: Color { blue }

    /// "signature ember gradient #F39057 → #E76F3A — progress, CTAs."
    static var emberGradient: LinearGradient {
        LinearGradient(colors: [ember, emberDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Scheme-adaptive surfaces
    // Native Jasper ships light AND dark; the glow language flips with the
    // system scheme: ink stage ↔ cream stage, cream type ↔ ink type, the
    // ember gradient constant across both.

    /// Stage/canvas color for the current scheme.
    static func stage(_ scheme: ColorScheme) -> Color { scheme == .dark ? ink : cream }

    /// Primary type color on the stage.
    static func text(_ scheme: ColorScheme) -> Color { scheme == .dark ? cream : ink }

    /// Glow-box fill (pairs with `boxBacking`).
    static func boxFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? cream.opacity(0.05) : Color.white.opacity(0.66)
    }

    /// Layer under the glow-box fill for depth.
    static func boxBacking(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.30)
    }

    /// Quiet chip/fill surface on the stage.
    static func chip(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? cream.opacity(0.08) : ink.opacity(0.06)
    }

    /// Hairline divider inside glow boxes.
    static func divider(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? cream.opacity(0.07) : ink.opacity(0.08)
    }

    /// Kicker/accent text — deep ember carries better on cream.
    static func kicker(_ scheme: ColorScheme) -> Color { scheme == .dark ? ember : emberDeep }

    // MARK: WHISPER_PLANS.md §1–2 — glow-box surfaces

    /// Opaque glow-box card fill: warm cream #FCF6E9 light / charcoal #24201D dark.
    /// Never a material, never clear glass.
    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.14, green: 0.125, blue: 0.115)
            : Color(red: 0.988, green: 0.964, blue: 0.912)
    }

    /// Quiet ink inset (overview blocks, meal cards): ink @ 0.045 / white @ 0.08.
    static func inset(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : ink.opacity(0.045)
    }

    /// Quieter inset for stacked rows (day rows): ink @ 0.035 / white @ 0.065.
    static func insetRow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.065) : ink.opacity(0.035)
    }
}

// MARK: - Marks

/// Jasper's mark — the REAL App Store icon (fetched + cached at runtime),
/// with the ember "J" monogram as the instant fallback underneath.
struct JasperMarkTile: View {
    var size: CGFloat = 52

    var body: some View {
        JasperAppIcon(size: size, cornerScale: 0.27)
            .shadow(color: JasperBrand.ember.opacity(0.45), radius: 12, y: 4)
    }
}

/// Whisper's mark — cream tile on the ink stage, ink tile on the cream one,
/// so it stays legible in both schemes.
struct WhisperMarkTile: View {
    var size: CGFloat = 52
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(JasperBrand.text(colorScheme))
            Image("WhisperLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.72, height: size * 0.72)
                .foregroundStyle(JasperBrand.stage(colorScheme))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Stage + glow box

/// Full-screen stage with slow-drifting ember blooms — ink in dark mode,
/// cream in light — the backdrop for every Jasper-branded moment. Static
/// under Reduce Motion.
struct JasperGlowStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var drift = false

    var body: some View {
        // The blooms carry fixed frames WIDER than sub-Max iPhones (460pt vs
        // a 393pt screen). As ZStack siblings they inflated the stage's
        // reported size, so every screen built on it laid out wider than the
        // glass and got trimmed on both edges. Overlays never participate in
        // layout sizing — the stage now always reports exactly the proposed
        // size and the blooms just bleed decoratively.
        JasperBrand.stage(colorScheme)
            .overlay {
                bloom(size: 460, opacity: colorScheme == .dark ? 0.30 : 0.20)
                    .offset(x: drift ? -70 : 60, y: drift ? -180 : -250)
                bloom(size: 380, opacity: colorScheme == .dark ? 0.16 : 0.12)
                    .offset(x: drift ? 130 : -110, y: drift ? 260 : 330)
            }
            .ignoresSafeArea()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
            }
            .allowsHitTesting(false)
    }

    private func bloom(size: CGFloat, opacity: Double) -> some View {
        RadialGradient(colors: [JasperBrand.ember.opacity(opacity), .clear],
                       center: .center, startRadius: 10, endRadius: size / 2)
            .frame(width: size, height: size)
    }
}

/// The ember glow box — WHISPER_PLANS.md §2, verbatim `emberGlowCard`:
/// an OPAQUE warm cream (light) / charcoal (dark) card wrapped in a 1pt warm
/// gradient hairline and the layered ember aura (two orange shadows + one
/// neutral contact shadow). `glow` scales ONLY the orange shadows — 1.0 for
/// hero/solo cards, 0.5 for stacked lists so auras don't bloom into each
/// other. Set `breathing` for the mandatory diet-generate loading state
/// (glow pulses 0.5 ↔ 1.0, easeInOut 1.4s, forever).
struct JasperGlowBox<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var glow: Double = 1
    var breathing: Bool = false
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathePhase = false

    private var liveGlow: Double {
        guard breathing, !reduceMotion else { return glow }
        return breathePhase ? 1.0 : 0.5
    }

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(JasperBrand.cardFill(colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [JasperBrand.ember.opacity(0.34), Color.white.opacity(0.06)]
                                        : [JasperBrand.ember.opacity(0.55), JasperBrand.emberDeep.opacity(0.16)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                    }
                    .shadow(color: JasperBrand.ember.opacity((colorScheme == .dark ? 0.26 : 0.32) * liveGlow),
                            radius: 16, y: 5)
                    .shadow(color: JasperBrand.emberDeep.opacity((colorScheme == .dark ? 0.10 : 0.14) * liveGlow),
                            radius: 34, y: 10)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.05), radius: 8, y: 2)
            }
            .onAppear {
                guard breathing, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    breathePhase = true
                }
            }
    }
}

/// The ember-glowing icon tile (`EmberGlowIcon`) that anchors every plan
/// header — WHISPER_PLANS.md §2. A bold rounded letter monogram can replace
/// the glyph (coach/app attribution tiles).
struct EmberGlowIcon: View {
    var systemName: String = "sparkles"
    var monogram: String? = nil
    var size: CGFloat = 40

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(RadialGradient(
                    colors: [JasperBrand.ember.opacity(colorScheme == .dark ? 0.44 : 0.42),
                             JasperBrand.ember.opacity(0.12)],
                    center: .center, startRadius: 1, endRadius: size * 0.78))
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .strokeBorder(JasperBrand.ember.opacity(colorScheme == .dark ? 0.36 : 0.38), lineWidth: 1)
                }
                .shadow(color: JasperBrand.ember.opacity(0.5), radius: 7, y: 2)
                .shadow(color: JasperBrand.emberDeep.opacity(0.22), radius: 14, y: 4)

            Group {
                if let monogram {
                    Text(monogram)
                        .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: size * 0.4, weight: .semibold))
                }
            }
            .foregroundStyle(colorScheme == .dark
                             ? Color(red: 0.99, green: 0.95, blue: 0.89)
                             : Color.black)
            .shadow(color: JasperBrand.ember.opacity(0.75), radius: 5)
        }
        .frame(width: size, height: size)
    }
}

/// Entrance for plan cards — WHISPER_PLANS.md §3: scale 0.96 → 1 + fade,
/// spring(response: 0.42, dampingFraction: 0.84).
struct JasperPlanEntrance: ViewModifier {
    @State private var landed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(landed ? 1 : 0.96)
            .opacity(landed ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { landed = true }
            }
    }
}

extension View {
    /// WHISPER_PLANS.md §3 entrance spring for plan glow cards.
    func jasperPlanEntrance() -> some View { modifier(JasperPlanEntrance()) }
}

/// Small-caps section label — WHISPER_PLANS.md §2 kickers: `.caption.bold`,
/// uppercase, tracking 0.7. Identity kickers ("WORKOUT PLAN") wear deep
/// ember on cream / ember on charcoal; inner section labels
/// ("WEEKLY STRUCTURE", "GROCERY LIST") are secondary.
struct JasperKicker: View {
    let text: String
    var secondary: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(secondary
                             ? JasperBrand.text(colorScheme).opacity(0.55)
                             : JasperBrand.kicker(colorScheme))
    }
}

/// 3-up glow tiles of live resource counts — the "what the token sees" grid
/// shared by the connect celebration and the coach access walkthrough.
struct JasperGlowCountsGrid: View {
    let resources: [JasperResourceSnapshot]
    @Environment(\.colorScheme) private var colorScheme

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 10),
         GridItem(.flexible(), spacing: 10),
         GridItem(.flexible(), spacing: 10)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(resources) { item in
                JasperGlowBox(cornerRadius: 16, glow: 0.35) {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(JasperBrand.ember)
                        Text("\(item.count)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(JasperBrand.text(colorScheme))
                            .contentTransition(.numericText())
                        Text(item.title)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

/// Shimmering stand-ins while live numbers load.
struct JasperGlowPlaceholderGrid: View {
    @Environment(\.colorScheme) private var colorScheme

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 10),
         GridItem(.flexible(), spacing: 10),
         GridItem(.flexible(), spacing: 10)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(spacing: 6) {
                    Circle()
                        .fill(JasperBrand.text(colorScheme).opacity(0.18))
                        .frame(width: 16, height: 16)
                    Capsule()
                        .fill(JasperBrand.text(colorScheme).opacity(0.24))
                        .frame(width: 38, height: 14)
                    Capsule()
                        .fill(JasperBrand.text(colorScheme).opacity(0.12))
                        .frame(width: 50, height: 7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(JasperBrand.chip(colorScheme).opacity(0.7), in: .rect(cornerRadius: 16))
                .phaseAnimator([0.9, 0.45]) { view, phase in
                    view.opacity(phase)
                } animation: { _ in .easeInOut(duration: 0.7) }
            }
        }
    }
}

// MARK: - Confirmation moment

/// The confirmation animation: two marks slide together, an ember ring
/// sweeps shut around them, the seal pops with a glow bloom, then the
/// headline lands and the content below staggers in. Jumps straight to the
/// finished frame under Reduce Motion.
struct JasperLinkConfirmation<LeftMark: View, Below: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let leftMark: () -> LeftMark
    @ViewBuilder let below: () -> Below

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// 0 blank · 1 marks in · 2 ring sweep + link · 3 seal · 4 headline · 5 below
    @State private var stage = 0
    @State private var ringSweep: CGFloat = 0
    @State private var pulse = false

    /// SE / mini class — the hero shrinks so the headline and live numbers
    /// stay above the fold instead of pushing the walkthrough into a crawl.
    private var isCompactPhone: Bool { UIScreen.main.bounds.height < 700 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .stroke(JasperBrand.ember.opacity(0.30), lineWidth: 1.5)
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulse ? 1.9 : 0.72)
                        .opacity(pulse ? 0 : 0.8)
                        .animation(stage >= 3
                                   ? .easeOut(duration: 1.7).repeatForever(autoreverses: false).delay(Double(index) * 0.6)
                                   : .default,
                                   value: pulse)
                }

                Circle()
                    .trim(from: 0, to: ringSweep)
                    .stroke(AngularGradient(colors: [JasperBrand.ember, JasperBrand.emberDeep, JasperBrand.ember],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: JasperBrand.ember.opacity(0.5), radius: 10)

                HStack(spacing: 13) {
                    leftMark()
                        .offset(x: stage >= 1 ? 0 : -46)
                        .opacity(stage >= 1 ? 1 : 0)
                    Image(systemName: "link")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(JasperBrand.ember)
                        .scaleEffect(stage >= 2 ? 1 : 0.2)
                        .opacity(stage >= 2 ? 1 : 0)
                    JasperMarkTile(size: 52)
                        .offset(x: stage >= 1 ? 0 : 46)
                        .opacity(stage >= 1 ? 1 : 0)
                }

                ZStack {
                    Circle()
                        .fill(JasperBrand.stage(colorScheme))
                        .frame(width: 38, height: 38)
                    Circle()
                        .fill(JasperBrand.emberGradient)
                        .frame(width: 30, height: 30)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(JasperBrand.ink)
                }
                .offset(x: 58, y: -42)
                .scaleEffect(stage >= 3 ? 1 : 0.1)
                .opacity(stage >= 3 ? 1 : 0)
                .shadow(color: JasperBrand.ember.opacity(0.6), radius: 10)
            }
            .scaleEffect(isCompactPhone ? 0.82 : 1)
            .frame(height: isCompactPhone ? 152 : 196)
            .padding(.top, isCompactPhone ? 2 : 8)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: stage)

            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: isCompactPhone ? 22 : 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(JasperBrand.text(colorScheme))
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 26)
            .opacity(stage >= 4 ? 1 : 0)
            .offset(y: stage >= 4 ? 0 : 12)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: stage)

            below()
                .opacity(stage >= 5 ? 1 : 0)
                .offset(y: stage >= 5 ? 0 : 16)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: stage)
        }
        .task { await run() }
    }

    private func run() async {
        guard stage == 0 else { return }
        if reduceMotion {
            ringSweep = 1
            stage = 5
            return
        }
        try? await Task.sleep(for: .milliseconds(90))
        stage = 1
        Haptics.tap()
        try? await Task.sleep(for: .milliseconds(480))
        stage = 2
        withAnimation(.easeInOut(duration: 0.7)) { ringSweep = 1 }
        try? await Task.sleep(for: .milliseconds(680))
        stage = 3
        pulse = true
        Haptics.success()
        try? await Task.sleep(for: .milliseconds(360))
        stage = 4
        try? await Task.sleep(for: .milliseconds(300))
        stage = 5
    }
}

// MARK: - Walkthrough (deck-tour skeleton, Jasper glow language)

struct JasperWalkthroughRow: Identifiable {
    let icon: String
    let title: String
    let detail: String
    var tint: Color? = nil
    var id: String { icon + title }
}

struct JasperWalkthroughSlide: Identifiable {
    let id: String
    let kicker: String
    let title: String
    var subtitle: String? = nil
    var rows: [JasperWalkthroughRow] = []
    var footnote: String? = nil
    /// Optional custom band rendered after the rows (native-look demos etc.).
    var extra: AnyView? = nil
}

/// Paged, glow-boxed walkthrough — the same slide skeleton as the meeting
/// deck tour (kicker, title, staggered lines, capsule dots, one continue
/// button), dressed in Jasper's orange-glow language. Page 0 is a custom
/// hero (the confirmation moment); the rest come from `slides`.
struct JasperGlowWalkthrough<Hero: View>: View {
    let slides: [JasperWalkthroughSlide]
    let onDone: () -> Void
    @ViewBuilder let hero: () -> Hero

    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0

    private var pageCount: Int { slides.count + 1 }

    var body: some View {
        ZStack {
            JasperGlowStage()
            VStack(spacing: 0) {
                header
                TabView(selection: $page) {
                    ScrollView {
                        hero()
                            .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                    .tag(0)
                    ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                        JasperWalkthroughSlideView(slide: slide, isActive: page == index + 1)
                            .tag(index + 1)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                bottomBar
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page
                              ? AnyShapeStyle(JasperBrand.emberGradient)
                              : AnyShapeStyle(JasperBrand.text(colorScheme).opacity(0.22)))
                        .frame(width: index == page ? 18 : 5, height: 5)
                }
            }
            .animation(.spring(duration: 0.3), value: page)
            Spacer()
            Button {
                Haptics.tap()
                onDone()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.65))
                    .frame(width: 32, height: 32)
                    .background(JasperBrand.chip(colorScheme), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close walkthrough")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var bottomBar: some View {
        Button {
            Haptics.tap()
            if page < pageCount - 1 {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { page += 1 }
            } else {
                onDone()
            }
        } label: {
            Text(page < pageCount - 1 ? "Continue" : "Done")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(JasperBrand.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(JasperBrand.emberGradient, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .shadow(color: JasperBrand.ember.opacity(0.35), radius: 18, y: 6)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

/// One walkthrough slide: kicker, big rounded title, glow-box rows that
/// stagger in the first time the page becomes active.
struct JasperWalkthroughSlideView: View {
    let slide: JasperWalkthroughSlide
    let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 6) {
                    JasperKicker(text: slide.kicker)
                    Text(slide.title)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(JasperBrand.text(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = slide.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 16)

                ForEach(Array(slide.rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row)
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 18)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8)
                                    .delay(0.12 + Double(index) * 0.09),
                                   value: revealed)
                }

                if let extra = slide.extra {
                    extra
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 18)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8)
                                    .delay(0.12 + Double(slide.rows.count) * 0.09),
                                   value: revealed)
                }

                if let footnote = slide.footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                        .opacity(revealed ? 1 : 0)
                        .animation(.easeOut(duration: 0.4)
                                    .delay(0.25 + Double(slide.rows.count) * 0.09),
                                   value: revealed)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .onAppear { if isActive { revealed = true } }
        .onChange(of: isActive) { _, active in
            if active { revealed = true }
        }
    }

    private func rowView(_ row: JasperWalkthroughRow) -> some View {
        JasperGlowBox(cornerRadius: 18, glow: 0.5) {
            HStack(spacing: 12) {
                Image(systemName: row.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(row.tint ?? JasperBrand.kicker(colorScheme))
                    .frame(width: 38, height: 38)
                    .background(JasperBrand.chip(colorScheme).opacity(0.8), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(JasperBrand.text(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }
}
```

---

End of blueprint — 7 production files, verbatim, plus stubs, asset spec, behaviour rules, and a real mount. Shared-brain sections (voice, formatting, knowledge, guardrails) are edited at https://mydailywhisper.com/jasper-brain and fold into both apps within about 5 minutes.
