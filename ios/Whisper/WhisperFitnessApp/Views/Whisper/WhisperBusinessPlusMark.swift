import SwiftUI

/// The same connected W-plus glyph used by the web Business+ workspace.
struct WhisperBusinessPlusMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let origin = CGPoint(x: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }
        var path = Path()
        path.move(to: point(2.4, 6.5))
        path.addLine(to: point(6.1, 16.5))
        path.addLine(to: point(9.35, 8.2))
        path.addLine(to: point(12.6, 16.5))
        path.addLine(to: point(16.4, 6.5))
        path.move(to: point(15.05, 10.3))
        path.addLine(to: point(22.2, 10.3))
        path.move(to: point(18.6, 6.7))
        path.addLine(to: point(18.6, 13.9))
        return path
    }
}
