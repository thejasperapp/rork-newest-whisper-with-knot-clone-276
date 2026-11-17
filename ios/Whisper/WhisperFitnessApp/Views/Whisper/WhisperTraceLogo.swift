import SwiftUI

/// The exact extracted brand mark, with a highlight travelling along its loops.
struct WhisperTraceLogo: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.whisperMediaActive) private var mediaActive
    @State private var startedAt: Date = .now
    var size: CGFloat = 56
    var lineWidth: CGFloat = 3.5
    var tint: Color? = nil
    var manualProgress: Double? = nil
    var outline: Bool = false

    var body: some View {
        Group {
            if reduceMotion {
                glyph.foregroundStyle(tint ?? WhisperTheme.ink(colorScheme))
            } else if let manualProgress {
                traced(from: 0, to: min(1, max(0, manualProgress)))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: scenePhase != .active || !mediaActive)) { context in
                    let phase = max(0, context.date.timeIntervalSince(startedAt)).truncatingRemainder(dividingBy: 1.8) / 1.8
                    let head = phase * 1.34
                    traced(from: max(0, head - 0.34), to: min(1, head))
                }
            }
        }
        .frame(width: size, height: size * 536 / 1040)
        .onChange(of: manualProgress == nil) { _, _ in startedAt = .now }
        .onAppear { startedAt = .now }
        .accessibilityHidden(true)
    }

    private var glyph: some View {
        Image("WhisperLogo").resizable().renderingMode(.template).scaledToFit()
    }

    private func traced(from: Double, to: Double) -> some View {
        let color = tint ?? WhisperTheme.ink(colorScheme)
        return ZStack {
            glyph.foregroundStyle(Color(white: colorScheme == .dark ? 0.29 : 0.73))
            if from == 0 && to >= 1 {
                glyph.foregroundStyle(color)
            } else if to > from {
                glyph.foregroundStyle(color)
                    .mask {
                        WhisperLogoTracePath().trim(from: from, to: to)
                            .stroke(.white, style: StrokeStyle(lineWidth: size * 0.108, lineCap: .round, lineJoin: .round))
                    }
            }
        }
    }
}
