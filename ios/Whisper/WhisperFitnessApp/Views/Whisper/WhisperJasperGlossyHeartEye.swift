import SwiftUI

/// Rounded red lacquer, with highlights scaled to the canonical eye anchors.
struct WhisperJasperGlossyHeartEye: View {
    var pulsing: Bool = false
    var excited: Bool = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !pulsing)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.45) / 1.45
            let first = exp(-pow((phase - 0.18) / 0.09, 2))
            let second = 0.65 * exp(-pow((phase - 0.42) / 0.10, 2))
            let bulge = pulsing ? (first + second) * (excited ? 0.28 : 0.18) : 0
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            WhisperEmberHeartEyeShape()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.24, blue: 0.36), Color(red: 0.98, green: 0.035, blue: 0.17), Color(red: 0.61, green: 0.015, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    ZStack {
                        Ellipse().fill(.white.opacity(0.72))
                            .frame(width: width * 0.19, height: height * 0.21)
                            .blur(radius: width * 0.045)
                            .position(x: width * 0.23, y: height * 0.21)
                        Ellipse().fill(.white.opacity(0.92))
                            .frame(width: width * 0.13, height: height * 0.23)
                            .rotationEffect(.degrees(-32))
                            .blur(radius: width * 0.025)
                            .position(x: width * 0.77, y: height * 0.19)
                        Ellipse().fill(Color(red: 1, green: 0.45, blue: 0.50).opacity(0.46))
                            .frame(width: width * 0.58, height: height * 0.22)
                            .blur(radius: width * 0.12)
                            .position(x: width * 0.38, y: height * 0.68)
                    }.clipShape(WhisperEmberHeartEyeShape())
                }
                .shadow(color: Color(red: 0.36, green: 0.005, blue: 0.055).opacity(0.35), radius: width * 0.055, y: height * 0.055)
        }
        .scaleEffect(x: 1 + bulge, y: 1 + bulge * 1.12)
        .offset(y: -bulge * 8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
