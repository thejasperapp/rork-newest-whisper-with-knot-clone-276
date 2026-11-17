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

    /// The Intelligence pearl finish; shared by every personality.
    static let intelligencePearl = WhisperEmberMascotPalette(
        soft: .white,
        mid: Color(red: 0.965, green: 0.973, blue: 0.983),
        deep: Color(red: 0.93, green: 0.945, blue: 0.965)
    )

    /// The Book of Whisper's Law robes — aged gold to match the tome.
    static let ancientGold = WhisperEmberMascotPalette(
        soft: Color(red: 0.97, green: 0.91, blue: 0.75),
        mid: Color(red: 0.85, green: 0.71, blue: 0.37),
        deep: Color(red: 0.54, green: 0.39, blue: 0.13)
    )

    /// The Dating hub's cupid costume — the same shading structure as every
    /// other ghost (soft → mid → deep gradient), tuned to the matchmaker pink.
    static let cupidPink = WhisperEmberMascotPalette(
        soft: Color(red: 1.00, green: 0.93, blue: 0.95),
        mid: Color(red: 0.96, green: 0.72, blue: 0.80),
        deep: Color(red: 0.90, green: 0.56, blue: 0.68)
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
    /// The romantic face rig — the cupid costume gets its OWN expression
    /// set mapped onto the shared choreography: soft round eyes at rest,
    /// outward-tilted heart eyes when he lights up, a flirty wink, a dreamy
    /// half-lidded glance, and adaptive raised-brow LINES that appear only
    /// when the eyes lift (never permanent eyebrows). Pose, blink, and
    /// transition beats stay identical to every other ghost.
    var smitten: Bool = false
    /// Opt-in so Meet and special costumes retain their existing artwork.
    var usesIntelligenceStyle: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.whisperMediaActive) private var mediaActive
    @Environment(\.scenePhase) private var scenePhase
    @State private var isMounted: Bool = false
    @State private var blinkToken: UUID = UUID()

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

    private var effectivePalette: WhisperEmberMascotPalette? {
        palette ?? (usesIntelligenceStyle ? .intelligencePearl : nil)
    }
    private var softColor: Color { effectivePalette?.soft ?? coachMode.softAccent }
    private var midColor: Color { effectivePalette?.mid ?? coachMode.accent }
    private var deepColor: Color { effectivePalette?.deep ?? coachMode.deepAccent }
    private var glowColor: Color {
        if smitten { return Color(red: 0.98, green: 0.24, blue: 0.52) }
        return usesIntelligenceStyle ? WhisperBrandGradient.accent : (palette?.mid ?? coachMode.accent)
    }
    private var hasWarmEyes: Bool { usesIntelligenceStyle && coachMode.resolved == .drillSergeant }
    private var hasReducedMotion: Bool { reduceMotion || !mediaActive || scenePhase != .active }
    /// Lifted-brow ink — the palette's deep tone so brows read as shading.
    private var browColor: Color { (palette?.deep ?? coachMode.deepAccent).opacity(0.85) }

    private var bodyFill: LinearGradient {
        LinearGradient(colors: [softColor, midColor, deepColor], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var targetExpression: WhisperEmberMascotExpression {
        guard cyclesExpressions, expression != .lookingDown else { return expression }
        return expressionCyclePhases[expressionPhase % expressionCyclePhases.count]
    }

    private var displayedExpression: WhisperEmberMascotExpression {
        hasReducedMotion ? targetExpression : renderedExpression
    }

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
        if usesIntelligenceStyle {
            WhisperKnotMascot(size: size, isActive: isActive, showsEyes: showsEyes, expression: expression)
        } else {
            legacyMascot
        }
    }

    private var legacyMascot: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                glowLayer
                ghostArtwork
                    .frame(width: size, height: ghostHeight)
                    .scaleEffect(x: hasReducedMotion ? 1 : (breathe ? 1.018 : 0.988), y: hasReducedMotion ? 1 : (breathe ? 1.024 : 0.986), anchor: .center)
                    .offset(y: hasReducedMotion ? 0 : floatY)
            }
            .frame(width: size, height: ghostHeight)
        }
        .frame(width: size, height: ghostHeight, alignment: .bottom)
        .accessibilityHidden(true)
        .onAppear {
            isMounted = true
            renderedExpression = targetExpression
            startAnimating()
        }
        .onDisappear {
            isMounted = false; blinkToken = UUID(); expressionTransitionToken &+= 1
            blinkTimer?.invalidate(); blinkTimer = nil
            expressionTimer?.invalidate(); expressionTimer = nil
            blink = false; eyeTransitionStage = .settled; renderedExpression = targetExpression
            breathe = false; floatY = 0; glowPulse = false
        }
        .onChange(of: hasReducedMotion) { _, _ in
            blinkToken = UUID()
            blinkTimer?.invalidate(); expressionTimer?.invalidate()
            expressionTransitionToken &+= 1
            blink = false; breathe = false; floatY = 0; glowPulse = false
            eyeTransitionStage = .settled; renderedExpression = targetExpression
            if !hasReducedMotion { startAnimating() }
        }
        .onChange(of: cyclesExpressions) { _, _ in scheduleExpressionCycle() }
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
            if showsEyes && smitten {
                smittenBrow(rect: leftEyeRect, side: .left)
                smittenBrow(rect: rightEyeRect, side: .right)
            }
            if usesIntelligenceStyle {
                WhisperJasperGhostAccessories(mode: coachMode)
                    .frame(width: size, height: ghostHeight)
            }
        }
        .compositingGroup()
    }

    /// The romantic eye art each expression wears when smitten. Hearts are
    /// RESERVED for the lit-up beats — the resting face is soft round eyes,
    /// curiosity becomes a flirty wink+heart, thinking goes dreamy.
    private enum SmittenEyeArt { case round, heart, wink, dreamy }

    private func smittenArt(for expression: WhisperEmberMascotExpression, side: EyeSide) -> SmittenEyeArt? {
        guard smitten else { return nil }
        return .heart
    }

    /// How high the brow LINE floats for an expression — nil means hidden.
    /// This is the "raised eyes" expression line, not a drawn-on eyebrow:
    /// it fades in and lifts only when the face genuinely lights up.
    private func browLift(for expression: WhisperEmberMascotExpression, side: EyeSide) -> CGFloat? {
        guard smitten else { return nil }
        switch expression {
        case .attentive: return 0.5
        case .happy: return 0.72
        case .delighted: return 1.0
        case .curious: return side == .right ? 0.85 : nil
        default: return nil
        }
    }

    /// One adaptive brow line — always mounted while smitten so its opacity,
    /// height, and tilt ANIMATE between expressions instead of popping.
    private func smittenBrow(rect: CGRect, side: EyeSide) -> some View {
        let lift = browLift(for: displayedExpression, side: side)
        let level: CGFloat = lift ?? 0
        let tiltMagnitude: Double = 8.0 + 6.0 * Double(level)
        let tilt: Double = side == .left ? -tiltMagnitude : tiltMagnitude
        let yDrop: CGFloat = rect.height * (0.08 + 0.26 * level)
        return WhisperEmberBrowShape()
            .stroke(browColor, style: StrokeStyle(lineWidth: max(1.1, 11 * scale), lineCap: .round))
            .frame(width: rect.width * 1.34 * scale, height: rect.height * 0.20 * scale)
            .rotationEffect(.degrees(tilt))
            .opacity(lift == nil ? 0 : 0.9)
            .position(
                x: rect.midX * scale,
                y: (rect.minY - yDrop) * scale
            )
            .allowsHitTesting(false)
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
        let art = smittenArt(for: displayedExpression, side: side)
        let canBlink = Date() >= suppressBlinkUntil && eyeTransitionStage == .settled
        let isBlinking = blink && canBlink
        let isLidBlink = isBlinking || eyeTransitionStage == .softBlink
        // Dreamy half-lid — the smitten "thinking" glance drops the lids.
        let dreamyLid: CGFloat = art == .dreamy ? 0.52 : 1
        let yScale = art == .heart ? 1 : (isLidBlink ? 0.075 : (stagedEyeScaleY(for: side) ?? pose.scaleY) * dreamyLid)
        let xScale = art == .heart ? 1 : (isLidBlink ? pose.scaleX * 1.06 : pose.scaleX)
        let blinkSlant: Double = isLidBlink ? (side == .left ? 7 : -7) : 0
        let xOffset = (art == .heart ? (side == .left ? -22.0 : 22.0) : pose.offsetX) * scale
        let yOffset = (pose.offsetY + (art == .dreamy ? rect.height * 0.10 : 0)) * scale
        let shapeStyle = isLidBlink ? EyeShapeStyle.exactMask : pose.shapeStyle

        ZStack {
            if let art {
                switch art {
                case .heart:
                    // Angled OUT like the reference — each heart leans away
                    // from the nose; pose transforms stack on top.
                    WhisperJasperGlossyHeartEye(pulsing: isMounted && !hasReducedMotion, excited: displayedExpression == .curious || displayedExpression == .delighted)
                        .rotationEffect(.degrees(side == .left ? -14 : 14))
                case .wink:
                    WhisperEmberWinkEyeShape()
                        .stroke(Color.black, style: StrokeStyle(lineWidth: max(1.5, 26 * scale), lineCap: .round))
                case .round, .dreamy:
                    WhisperEmberStandardEyeShape().fill(Color.black)
                }
            } else {
                WhisperEmberStandardEyeShape().fill(Color.black)
                    .overlay { if hasWarmEyes { WhisperJasperEyeGlow().clipShape(WhisperEmberStandardEyeShape()) } }
                    .opacity(shapeStyle == .exactMask ? 1 : 0)
                WhisperEmberHappyEyeShape().fill(Color.black)
                    .overlay { if hasWarmEyes { WhisperJasperEyeGlow().clipShape(WhisperEmberHappyEyeShape()) } }
                    .opacity(shapeStyle == .happySmile ? 1 : 0)
                WhisperEmberAngryEyeShape(isLeft: side == .left).fill(Color.black)
                    .overlay { if hasWarmEyes { WhisperJasperEyeGlow().clipShape(WhisperEmberAngryEyeShape(isLeft: side == .left)) } }
                    .opacity(shapeStyle == .sternGlare ? 1 : 0)
            }
        }
        .frame(
            width: rect.width * scale * smittenShapeWidth(art: art, pose: pose),
            height: rect.height * scale * smittenShapeHeight(art: art, pose: pose)
        )
        .offset(y: rect.height * scale * pose.shapeYOffset)
        .transaction { $0.disablesAnimations = true }
        .scaleEffect(x: xScale, y: yScale, anchor: .center)
        .rotationEffect(.degrees(pose.rotation + blinkSlant))
        .offset(x: xOffset, y: yOffset)
        .position(x: rect.midX * scale, y: rect.midY * scale)
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private func smittenShapeWidth(art: SmittenEyeArt?, pose: EyePose) -> CGFloat {
        switch art {
        case .heart: return 2.05
        case .wink: return 1.30
        case .round, .dreamy: return pose.shapeWidth
        case nil: return pose.shapeWidth
        }
    }

    private func smittenShapeHeight(art: SmittenEyeArt?, pose: EyePose) -> CGFloat {
        switch art {
        case .heart: return 1.22
        case .wink: return 0.55
        case .round, .dreamy: return pose.shapeHeight
        case nil: return pose.shapeHeight
        }
    }

    private func startAnimating() {
        guard isMounted, !hasReducedMotion else { return }
        withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { breathe = true }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { floatY = -size * 0.035 }
        restartGlow()
        scheduleBlink()
        scheduleExpressionCycle()
    }

    private func restartGlow() {
        guard isMounted, !hasReducedMotion, !usesIntelligenceStyle, !smitten else { return }
        glowPulse = false
        withAnimation(.easeInOut(duration: isActive ? 1.05 : 2.45).repeatForever(autoreverses: true)) {
            glowPulse = true
        }
    }

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        guard isMounted, !hasReducedMotion, !smitten else { blink = false; return }
        let token = UUID(); blinkToken = token
        blinkTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 2.8...5.2), repeats: false) { _ in
            Task { @MainActor in
                guard isMounted, !hasReducedMotion, blinkToken == token else { return }
                withAnimation(.easeInOut(duration: 0.10)) { blink = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                    guard isMounted, !hasReducedMotion, blinkToken == token else { return }
                    withAnimation(.easeInOut(duration: 0.12)) { blink = false }
                    scheduleBlink()
                }
            }
        }
    }

    private func scheduleExpressionCycle() {
        expressionTimer?.invalidate()
        guard isMounted, cyclesExpressions, !hasReducedMotion else { expressionPhase = 0; return }
        expressionTimer = Timer.scheduledTimer(withTimeInterval: 3.65, repeats: true) { _ in
            Task { @MainActor in transitionToNextExpression() }
        }
    }

    private func transitionToNextExpression() {
        guard isMounted, cyclesExpressions, !hasReducedMotion else { return }
        withAnimation(.easeInOut(duration: 0.18)) { expressionPhase &+= 1 }
    }

    private func transitionExpression(to newExpression: WhisperEmberMascotExpression) {
        expressionTransitionToken &+= 1
        guard renderedExpression != newExpression else { eyeTransitionStage = .settled; blink = false; return }
        if smitten { renderedExpression = newExpression; eyeTransitionStage = .settled; blink = false; return }
        if hasReducedMotion {
            expressionTransitionToken &+= 1
            renderedExpression = newExpression; eyeTransitionStage = .settled; blink = false
            return
        }
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
            guard isMounted, !hasReducedMotion, token == expressionTransitionToken else { return }
            withAnimation(animation) { eyeTransitionStage = stage }
        }
    }

    private func settleExpression(to newExpression: WhisperEmberMascotExpression, token: Int, after delay: TimeInterval, animation: Animation) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isMounted, !hasReducedMotion, token == expressionTransitionToken else { return }
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

/// Heart eye — full round lobes, a DEEP cleft, and a tapered point like the
/// reference art. Drawn upright; the render tilts each side outward. Blink
/// squash and every pose transform apply on top, so the hearts still act.
struct WhisperEmberHeartEyeShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let sx = rect.width / 32.0
        let sy = rect.height / 30.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var p = Path()
        p.move(to: pt(16, 7.4))
        p.addCurve(to: pt(8.6, 0), control1: pt(14.2, 2.6), control2: pt(11.9, 0))
        p.addCurve(to: pt(0, 8.8), control1: pt(3.9, 0), control2: pt(0, 3.9))
        p.addCurve(to: pt(16, 30), control1: pt(0, 16.6), control2: pt(8.4, 22.6))
        p.addCurve(to: pt(32, 8.8), control1: pt(23.6, 22.6), control2: pt(32, 16.6))
        p.addCurve(to: pt(23.4, 0), control1: pt(32, 3.9), control2: pt(28.1, 0))
        p.addCurve(to: pt(16, 7.4), control1: pt(20.1, 0), control2: pt(17.8, 2.6))
        p.closeSubpath()
        return p
    }
}

/// The flirty wink — one closed-lash arc bowing gently downward.
private struct WhisperEmberWinkEyeShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY - rect.height * 0.12))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.12),
            control: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.42)
        )
        return p
    }
}

/// A raised brow LINE — one arched stroke; the call site positions, tilts,
/// and fades it per expression so it reads as expression, not an eyebrow.
private struct WhisperEmberBrowShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.35)
        )
        return p
    }
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
