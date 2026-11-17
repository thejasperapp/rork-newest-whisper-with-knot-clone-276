import SwiftUI

/// Whisper's branded voice glyph — a living, blobby waveform that replaces
/// stock mic icons on every Jasper surface. Five soft capsules breathe in a
/// rolling wave over a faint blob glow, tinted to the active personality.
/// `active` speeds up and brightens the motion (live voice / capturing).
struct WhisperJasperVoiceGlyph: View {
    /// Personality accent driving the bars and glow.
    var tint: Color
    /// Optional explicit bar colour (e.g. black bars on an accent-filled button).
    var barColor: Color? = nil
    var size: CGFloat = 18
    var active: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate * (active ? 3.4 : 1.5)
            let bars: [CGFloat] = (0..<5).map { index in
                let phase = t + Double(index) * 0.85
                // Two offset sines make the motion blobby instead of metronomic.
                let wave = (sin(phase) + sin(phase * 1.63 + 1.4)) / 2
                let normalized = 0.30 + 0.70 * (wave + 1) / 2
                return size * normalized
            }
            ZStack {
                // The futuristic blob glow breathing behind the bars.
                Circle()
                    .fill(tint.opacity(active ? 0.34 : 0.2))
                    .frame(width: size * 1.5, height: size * 1.5)
                    .blur(radius: size * 0.28)
                    .scaleEffect(1 + 0.08 * sin(t * 0.9))
                HStack(spacing: size * 0.08) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(barColor ?? tint)
                            .frame(
                                width: size * 0.13,
                                height: max(size * 0.22, bars[index])
                            )
                    }
                }
            }
            .frame(width: size * 1.2, height: size * 1.2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
