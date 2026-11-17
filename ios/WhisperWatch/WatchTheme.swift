import SwiftUI

/// Whisper's brand system on the wrist — the black canvas is the desk,
/// content sits on cream PAPER cards with ink type (the exact language the
/// home-screen widgets speak), ghost mint + deep mint accents, warm heat.
enum WatchTheme {
    static let ink = Color(red: 0.129, green: 0.110, blue: 0.102)
    static let cream = Color(red: 0.984, green: 0.957, blue: 0.894)
    static let mint = Color(red: 0.725, green: 0.953, blue: 0.863)
    static let deepMint = Color(red: 0.055, green: 0.624, blue: 0.463)
    static let heat = Color(red: 0.953, green: 0.565, blue: 0.341)

    /// Dim cream — for text sitting directly on the black canvas.
    static var dim: Color { cream.opacity(0.55) }
    /// Dim ink — secondary text sitting ON a paper card.
    static var inkDim: Color { ink.opacity(0.55) }
}

/// Cream paper card — the widget design language on the wrist. Every piece
/// of content sits on one of these; ink text, deep-mint accents.
struct WatchPaperCard<Content: View>: View {
    var padding: CGFloat = 10
    /// Optional wash laid over the cream (e.g. mint for quote cards).
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(WatchTheme.cream)
                    if let tint {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tint)
                    }
                }
            }
    }
}

/// Mint count capsule — ink text on ghost mint, the brand's badge.
struct WatchMintBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(WatchTheme.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(WatchTheme.mint, in: Capsule())
    }
}

/// Jasper's expression vocabulary — the same moods the in-app living mascot
/// cycles through.
enum WatchExpression {
    case wide, happy, wink, sleepy, curious
}

/// The REAL Jasper Intelligence mascot on the wrist — the production
/// template silhouette (`WhisperEmberGhostBody`, 846×839) tinted with the
/// Original personality's mint gradient (#EDFFF5 → #C2FCE6 → #94D1B8), the
/// soft top-left sheen, and the true eye rig at the template's exact eye
/// rectangles — breathing, blinking, AND cycling expressions exactly like
/// the living mascot in the app.
struct WatchJasperGhost: View {
    var size: CGFloat
    var tilt: Double = 0
    /// When true (default) the ghost drifts through expressions on his own.
    var expressive: Bool = true

    @State private var breathing: Bool = false
    @State private var blinking: Bool = false
    @State private var expression: WatchExpression = .wide

    private static let srcW: CGFloat = 846
    private static let srcH: CGFloat = 839
    private static let leftEye = CGRect(x: 273, y: 192, width: 101, height: 159)
    private static let rightEye = CGRect(x: 463, y: 192, width: 100, height: 159)

    private static let soft = Color(red: 0.93, green: 1.00, blue: 0.96)
    private static let mid = Color(red: 0.76, green: 0.99, blue: 0.90)
    private static let deep = Color(red: 0.58, green: 0.82, blue: 0.72)

    private var height: CGFloat { size * Self.srcH / Self.srcW }
    private var scale: CGFloat { size / Self.srcW }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("WhisperEmberGhostBody")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(
                    LinearGradient(
                        colors: [Self.soft, Self.mid, Self.deep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: height)
                .shadow(color: Self.deep.opacity(0.55), radius: size * 0.1, y: size * 0.03)
                .overlay {
                    Image("WhisperEmberGhostBody")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(
                            RadialGradient(
                                colors: [Color.white.opacity(0.32), .clear],
                                center: UnitPoint(x: 0.38, y: 0.20),
                                startRadius: 1,
                                endRadius: size * 0.62
                            )
                        )
                }

            eye(Self.leftEye, isLeft: true)
            eye(Self.rightEye, isLeft: false)
        }
        .frame(width: size, height: height)
        .rotationEffect(.degrees(tilt))
        .scaleEffect(breathing ? 1.03 : 0.97)
        .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: breathing)
        .onAppear { breathing = true }
        .task { await blinkLoop() }
        .task { await expressionLoop() }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func eye(_ rect: CGRect, isLeft: Bool) -> some View {
        let w = rect.width * scale
        let h = rect.height * scale
        Group {
            switch expression {
            case .wide:
                Ellipse().fill(Color.black)
                    .frame(width: w, height: h)
            case .happy:
                WatchHappyEyeShape().fill(Color.black)
                    .frame(width: w, height: h)
            case .wink:
                if isLeft {
                    WatchHappyEyeShape().fill(Color.black)
                        .frame(width: w, height: h)
                } else {
                    Capsule().fill(Color.black)
                        .frame(width: w * 1.05, height: max(1.5, h * 0.14))
                        .offset(y: h * 0.1)
                }
            case .sleepy:
                Ellipse().fill(Color.black)
                    .frame(width: w, height: h * 0.42)
                    .offset(y: h * 0.2)
            case .curious:
                Ellipse().fill(Color.black)
                    .frame(width: w * 0.92, height: h * 0.9)
                    .offset(x: -w * 0.16, y: -h * 0.04)
            }
        }
        .scaleEffect(x: blinking ? 1.06 : 1, y: blinking ? 0.075 : 1)
        .position(x: rect.midX * scale, y: rect.midY * scale)
    }

    /// Random-interval blink, exactly the cadence the app's mascot keeps.
    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.8...5.2)))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.1)) { blinking = true }
            try? await Task.sleep(for: .milliseconds(130))
            withAnimation(.easeInOut(duration: 0.12)) { blinking = false }
        }
    }

    /// The living mascot's idle acting — drift between moods, throw the
    /// occasional wink, get sleepy for a beat, snap back happy.
    private func expressionLoop() async {
        guard expressive else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 3.5...7.5)))
            guard !Task.isCancelled else { return }
            let roll = Int.random(in: 0..<10)
            let next: WatchExpression =
                roll < 4 ? .happy : roll < 7 ? .wide : roll < 8 ? .curious : roll < 9 ? .wink : .sleepy
            withAnimation(.easeInOut(duration: 0.22)) { expression = next }
            // Winks and dozes are beats, not states — snap back happy.
            if next == .wink || next == .sleepy {
                try? await Task.sleep(for: .milliseconds(next == .wink ? 900 : 1700))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.2)) { expression = .happy }
            }
        }
    }
}

/// The production happy-eye path — same curves as the app's living mascot.
struct WatchHappyEyeShape: Shape {
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

/// Kicker line — deep-mint dot + tracked caps, the brand header. Sits on
/// the black canvas in cream.
struct WatchKicker: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(WatchTheme.deepMint).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(WatchTheme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
