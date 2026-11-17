import SwiftUI

/// Tiny "k/N" capsule pill used to number self-thread replies and
/// "Add to thread" parts in the composer. Centralized so every surface
/// renders identically (composer, feed card header, post detail block,
/// comment row).
struct WhisperThreadPositionPill: View {
    let index: Int
    let total: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("\(index)/\(total)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(WhisperTheme.card(colorScheme)))
            .monospacedDigit()
    }
}
