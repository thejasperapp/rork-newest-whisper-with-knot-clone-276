import SwiftUI

/// Legacy specialist rendering preserves their distinct colours and expressions.
/// The main Knot identity uses the supplied complete media set instead.
struct WhisperKnotSpecialistMascot: View {
    enum Motion { case idle, working, making, milestone }

    var size: CGFloat = 120
    var isActive: Bool = false
    var showsEyes: Bool = true
    var expression: WhisperEmberMascotExpression = .calm
    var showsOrb: Bool = false
    var voiceLevel: CGFloat = 0
    var bodyColor: Color? = nil
    var motion: Motion? = nil
    var milestoneDate: Date? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.whisperMediaActive) private var mediaActive
    @Environment(\.scenePhase) private var scenePhase
    @State private var epoch = Date()
    @State private var visible = false

    private var running: Bool { visible && !reduceMotion && mediaActive && scenePhase == .active }
    private var amber: Color { Color(red: 1, green: 0.53, blue: 0.13) }
    private var safeLevel: CGFloat { voiceLevel.isFinite ? min(1, max(0, voiceLevel)) : 0 }
    private var requestedMotion: Motion {
        if let motion { return motion }
        if showsOrb { return .making }
        if expression == .happy || expression == .delighted { return .milestone }
        if isActive || expression == .thinking || expression == .focused || expression == .skeptical { return .working }
        return .idle
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: size < 80 ? 1.0 / 30 : 1.0 / 60, paused: !running)) { context in
            puppet(at: context.date)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false).accessibilityHidden(true)
        .onAppear { epoch = Date(); visible = true }
        .onDisappear { visible = false }
        .onChange(of: requestedMotion) { _, _ in epoch = Date() }
        .onChange(of: running) { _, active in if active { epoch = Date() } }
    }

    private func puppet(at date: Date) -> some View {
        let t = running ? max(0, date.timeIntervalSince(epoch)) : 0
        let celebrationTime = max(0, date.timeIntervalSince(milestoneDate ?? epoch))
        let celebrating = requestedMotion == .milestone && celebrationTime < 5
        let mode: Motion = celebrating ? .milestone : (requestedMotion == .milestone ? .idle : requestedMotion)
        let breath = sin(t * 2 * .pi / (mode == .working ? 3.8 : 4.8))
        let bounce = mode == .milestone ? sin(celebrationTime * 2 * .pi / 1.2) : 0
        let lift = running ? -size * (0.012 * breath + 0.023 * max(0, bounce)) : 0
        let tilt = running ? (mode == .milestone ? 5 * bounce : (mode == .working ? 0.6 : 1.4) * sin(t * 1.1)) : 0
        let angle = t * 2 * .pi / (mode == .milestone ? 3.6 : 4.8)
        let depth = sin(angle)
        let accessory = mode == .making || mode == .milestone
        let pulse = running ? 0.88 + 0.12 * breath : 1
        return ZStack {
            // Working deliberately has no large halo, matching its reference.
            if mode != .working {
                Image("KnotNeutralV3").renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(amber)
                    .frame(width: size, height: size)
                    .blur(radius: size * 0.075)
                    .opacity(0.52 * pulse)
                    .scaleEffect(1.025)
            }
            if accessory && depth < 0 { companion(mode: mode, angle: angle, depth: depth) }
            ZStack {
                bodyLayer()
                if showsEyes {
                    eye("KnotEyeLeftV3", centerX: 0.363, t: t, mode: mode)
                    eye("KnotEyeRightV3", centerX: 0.635, t: t, mode: mode)
                }
            }
            .scaleEffect(x: 1 - (running ? 0.006 * breath : 0),
                         y: 1 + (running ? 0.012 * breath + safeLevel * 0.025 : 0), anchor: .bottom)
            .rotationEffect(.degrees(tilt))
            .offset(y: lift)
            if accessory && depth >= 0 { companion(mode: mode, angle: angle, depth: depth) }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private func bodyLayer() -> some View {
        if let bodyColor {
            // Lift the near-black yarn before tinting; eyes keep their amber hue.
            layer("KnotBodyV3").saturation(0).brightness(0.46).colorMultiply(bodyColor)
                .mask { layer("KnotBodyV3") }
        } else { layer("KnotBodyV3") }
    }

    private func eye(_ name: String, centerX: CGFloat, t: Double, mode: Motion) -> some View {
        // Smooth, short eyelid closure rather than a timer-driven texture swap.
        let cycle = t.truncatingRemainder(dividingBy: 5.4)
        let blink = running && cycle > 4.8 && cycle < 5.08 ? sin((cycle - 4.8) / 0.28 * .pi) : 0
        let focus: CGFloat = mode == .working ? 0.84 : (mode == .milestone ? 0.90 : 1)
        let gazeX: CGFloat = running ? CGFloat(sin(t * 0.65)) * (mode == .working ? 0.004 : 0.009) : 0
        let gazeY: CGFloat = expression == .lookingDown ? 0.025 : (mode == .working ? -0.006 : 0)
        return layer(name)
            .scaleEffect(x: 1, y: max(0.06, focus * (1 - CGFloat(blink) * 0.94)), anchor: UnitPoint(x: centerX, y: 0.382))
            .offset(x: size * gazeX, y: size * gazeY)
            .shadow(color: amber.opacity(mode == .working ? 0.20 : 0.40), radius: size * 0.012)
    }

    private func companion(mode: Motion, angle: Double, depth: Double) -> some View {
        let star = mode == .milestone
        return Group {
            if star {
                Image("KnotMilestoneStarV3").renderingMode(.original).resizable().scaledToFit()
                    .shadow(color: amber.opacity(0.7), radius: size * 0.028)
                    .rotationEffect(.degrees(running ? angle * 180 / .pi : -12))
            } else {
                // Translucent creation orb, with its own highlight and amber rim.
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.86), amber.opacity(0.25), .black.opacity(0.28)], center: .topLeading, startRadius: 0, endRadius: size * 0.21))
                    .overlay { Circle().strokeBorder(.white.opacity(0.6), lineWidth: max(0.5, size * 0.005)) }
                    .overlay(alignment: .topLeading) {
                        Ellipse().fill(.white.opacity(0.78)).frame(width: size * 0.055, height: size * 0.025)
                            .rotationEffect(.degrees(-35)).padding(size * 0.034)
                    }
                    .shadow(color: amber.opacity(0.45), radius: size * 0.025)
            }
        }
        .frame(width: size * (star ? 0.26 : 0.22), height: size * (star ? 0.26 : 0.22))
        .scaleEffect(0.90 + 0.12 * depth)
        .opacity(0.84 + 0.16 * (depth + 1) / 2)
        .position(x: size * (0.5 + 0.39 * cos(angle)), y: size * (0.23 + 0.13 * depth))
    }

    private func layer(_ name: String) -> some View {
        Image(name).renderingMode(.original).resizable().scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Only controls receive glass. Content cards keep their existing opaque surface.
struct WhisperKnotGlassPill: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                .overlay { Capsule().strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.18), lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.12), lineWidth: 1) }
        }
    }
}
