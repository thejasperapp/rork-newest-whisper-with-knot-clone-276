import SwiftUI

/// Round the full-bleed upper edge; the bottom meets the stationary tab bar.
struct WhisperTabPageClip: Shape {
    let radius: CGFloat
    let top: CGFloat
    let bottom: CGFloat

    func path(in rect: CGRect) -> Path {
        let expanded = CGRect(x: rect.minX, y: rect.minY - top, width: rect.width, height: rect.height + top + bottom)
        return UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous).path(in: expanded)
    }
}
