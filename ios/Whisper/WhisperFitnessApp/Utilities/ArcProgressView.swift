import SwiftUI

struct ArcProgressView: View {
    let progress: Double
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat

    private let startAngle: Double = 135
    private let totalAngle: Double = 270

    var body: some View {
        ZStack {
            Circle()
                .trim(from: trimStart, to: trimEnd)
                .stroke(Color.black.opacity(0.1), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(startAngle))

            Circle()
                .trim(from: trimStart, to: trimStart + (trimEnd - trimStart) * min(progress, 1.0))
                .stroke(Color.black, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(startAngle))
        }
        .frame(width: size, height: size)
    }

    private var trimStart: Double { 0 }
    private var trimEnd: Double { totalAngle / 360.0 }
}
