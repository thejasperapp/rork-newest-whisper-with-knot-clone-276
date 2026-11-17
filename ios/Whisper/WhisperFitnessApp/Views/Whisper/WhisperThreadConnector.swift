import SwiftUI

/// Drawn behind a measured row; the rail never contributes height to a lazy stack.
struct WhisperThreadConnector: Shape {
    var startY: CGFloat = 48
    var bendsToReply: Bool = false

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 22
        let bottom = rect.maxY
        guard bottom > startY else { return path }
        path.move(to: CGPoint(x: x, y: startY))
        if bendsToReply {
            let radius: CGFloat = 12
            path.addLine(to: CGPoint(x: x, y: max(startY, bottom - radius)))
            path.addQuadCurve(to: CGPoint(x: x + radius, y: bottom),
                              control: CGPoint(x: x, y: bottom))
            path.addLine(to: CGPoint(x: x + 16, y: bottom))
        } else {
            path.addLine(to: CGPoint(x: x, y: bottom))
        }
        return path
    }
}
