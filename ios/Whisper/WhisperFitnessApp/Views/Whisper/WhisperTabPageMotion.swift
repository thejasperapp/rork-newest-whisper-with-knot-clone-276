import SwiftUI

/// Interpolates progress itself, so corners stay rounded until the last pixels
/// of a settle instead of flattening for the entire release animation.
struct WhisperTabPageMotion: ViewModifier, Animatable {
    var progress: CGFloat
    let moving: Bool
    let isSource: Bool
    let direction: Int
    let restingOffset: CGFloat
    let size: CGSize
    let insets: EdgeInsets
    let reduceMotion: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let radius = moving && !reduceMotion ? WhisperTabPagingState.cornerRadius(progress: progress, width: size.width) : 0
        content
            .clipShape(WhisperTabPageClip(radius: radius, top: insets.top, bottom: insets.bottom))
            .offset(x: moving ? WhisperTabPagingState.offset(isSource: isSource, direction: direction, progress: progress, width: size.width) : restingOffset)
    }
}
