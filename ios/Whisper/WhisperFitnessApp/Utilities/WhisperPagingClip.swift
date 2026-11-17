import SwiftUI

/// Masks horizontal page overflow while retaining full-bleed safe-area drawing.
struct WhisperPagingClip: Shape {
    var radius: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: CGRect(x: rect.minX, y: rect.minY - top, width: rect.width, height: rect.height + top + bottom), cornerRadius: radius)
    }
}
