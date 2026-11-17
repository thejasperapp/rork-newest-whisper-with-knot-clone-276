import SwiftUI

/// A reveal guide along the supplied mark's centerline. The extracted logo,
/// not this guide, defines the visible silhouette and stroke weight.
struct WhisperLogoTracePath: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (x - 248) / 1040 * rect.width,
                    y: rect.minY + (y - 232) / 536 * rect.height)
        }
        var path = Path()
        path.move(to: p(348, 717))
        path.addCurve(to: p(576, 430), control1: p(466, 621), control2: p(576, 518))
        path.addCurve(to: p(441, 284), control1: p(586, 345), control2: p(519, 284))
        path.addCurve(to: p(299, 430), control1: p(365, 284), control2: p(299, 348))
        path.addCurve(to: p(592, 722), control1: p(299, 550), control2: p(462, 722))
        path.addCurve(to: p(867, 490), control1: p(716, 722), control2: p(867, 575))
        path.addCurve(to: p(768, 391), control1: p(867, 435), control2: p(821, 391))
        path.addCurve(to: p(668, 490), control1: p(715, 391), control2: p(668, 435))
        path.addCurve(to: p(944, 722), control1: p(668, 577), control2: p(818, 722))
        path.addCurve(to: p(1237, 430), control1: p(1074, 722), control2: p(1237, 550))
        path.addCurve(to: p(1098, 284), control1: p(1237, 348), control2: p(1173, 284))
        path.addCurve(to: p(961, 430), control1: p(1020, 284), control2: p(951, 345))
        path.addCurve(to: p(1188, 717), control1: p(961, 535), control2: p(1095, 646))
        return path
    }
}
