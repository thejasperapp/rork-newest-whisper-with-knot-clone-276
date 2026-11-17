import SwiftUI

/// The outer rail belongs to the parent; siblings join it rather than each other.
struct WhisperThreadBranchConnector: Shape {
    var continues: Bool

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let x: CGFloat = -2
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: 14))
        path.addQuadCurve(to: CGPoint(x: 6, y: 22), control: CGPoint(x: x, y: 22))
        if continues {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        return path
    }
}
