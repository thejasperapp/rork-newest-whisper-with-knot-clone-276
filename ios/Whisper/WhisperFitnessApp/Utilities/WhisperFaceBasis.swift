import CoreGraphics

/// Mouth disambiguates the two eye-axis directions, including rolls past 90 degrees.
nonisolated struct WhisperFaceBasis {
    let distance: CGFloat
    let angle: CGFloat
    let up: CGVector

    init?(left: CGPoint, right: CGPoint, mouth: CGPoint) {
        guard [left.x, left.y, right.x, right.y, mouth.x, mouth.y].allSatisfy(\.isFinite) else { return nil }
        let length = hypot(right.x - left.x, right.y - left.y)
        guard length.isFinite, length > 4 else { return nil }
        var x = (right.x - left.x) / length
        var y = (right.y - left.y) / length
        let mid = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        if -y * (mid.x - mouth.x) + x * (mid.y - mouth.y) < 0 { x = -x; y = -y }
        distance = length
        angle = atan2(y, x)
        up = CGVector(dx: -y, dy: x)
    }
}
