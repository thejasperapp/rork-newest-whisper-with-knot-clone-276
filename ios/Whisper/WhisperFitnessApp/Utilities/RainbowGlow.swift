import SwiftUI

private let rainbowGlowColors: [Color] = [
    Color(red: 0.45, green: 0.78, blue: 1.0),
    Color(red: 0.72, green: 0.52, blue: 1.0),
    Color(red: 1.0, green: 0.45, blue: 0.91),
    Color(red: 1.0, green: 0.65, blue: 0.45),
    Color(red: 1.0, green: 0.97, blue: 0.39),
    Color(red: 0.52, green: 1.0, blue: 0.72),
    Color(red: 0.39, green: 0.91, blue: 1.0),
    Color(red: 0.45, green: 0.78, blue: 1.0),
]

struct RainbowGlowBackground: View {
    var cornerRadius: CGFloat = 20
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: rainbowGlowColors),
                        center: .center,
                        angle: .degrees(rotation)
                    ),
                    lineWidth: 2
                )
                .blur(radius: 1)

            RoundedRectangle(cornerRadius: cornerRadius + 2)
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: rainbowGlowColors.map { $0.opacity(0.45) }),
                        center: .center,
                        angle: .degrees(rotation)
                    ),
                    lineWidth: 6
                )
                .blur(radius: 12)
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

extension View {
    func rainbowGlow(cornerRadius: CGFloat = 20) -> some View {
        background(RainbowGlowBackground(cornerRadius: cornerRadius))
    }
}
