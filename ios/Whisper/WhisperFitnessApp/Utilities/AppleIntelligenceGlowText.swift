import SwiftUI

struct AppleIntelligenceGlowText: View {
    let text: String
    @State private var gradientPhase: CGFloat = 0

    private let glowColors: [Color] = [
        Color(red: 0.45, green: 0.78, blue: 1.0),
        Color(red: 0.72, green: 0.52, blue: 1.0),
        Color(red: 1.0, green: 0.45, blue: 0.91),
        Color(red: 1.0, green: 0.65, blue: 0.45),
        Color(red: 1.0, green: 0.97, blue: 0.39),
        Color(red: 0.52, green: 1.0, blue: 0.72),
        Color(red: 0.39, green: 0.91, blue: 1.0),
        Color(red: 0.45, green: 0.78, blue: 1.0),
    ]

    var body: some View {
        ZStack {
            Text(text)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: glowColors,
                        startPoint: UnitPoint(x: gradientPhase, y: 0),
                        endPoint: UnitPoint(x: gradientPhase + 1.0, y: 1)
                    )
                )

            Text(text)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: glowColors,
                        startPoint: UnitPoint(x: gradientPhase, y: 0),
                        endPoint: UnitPoint(x: gradientPhase + 1.0, y: 1)
                    )
                )
                .blur(radius: 12)
                .opacity(0.5)
        }
        .onAppear {
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                gradientPhase = 1.0
            }
        }
    }
}
