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
