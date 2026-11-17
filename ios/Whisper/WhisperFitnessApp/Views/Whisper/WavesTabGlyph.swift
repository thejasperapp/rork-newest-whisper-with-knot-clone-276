import SwiftUI

/// The custom tab mark for WAVES — Whisper's short-video surface. A thick
/// rounded squircle with a rounded play wedge inside; selecting it fills the
/// squircle with solid tab ink and a contrasting wedge, retaining its
/// full-size mark and reduced-motion-aware selection spring.
struct WavesTabGlyph: View {
    let isSelected: Bool
    let ink: Color
    var selectedCutout: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(ink)
                wedge(selectedCutout)
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(ink, lineWidth: 2.3)
                wedge(ink)
            }
        }
        .frame(width: 27, height: 27)
        .scaleEffect(isSelected && !reduceMotion ? 1.08 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.55), value: isSelected)
    }

    /// Rounded play wedge — filled triangle with round joins so the corners
    /// read soft at tab-bar size.
    private func wedge(_ tone: Color) -> some View {
        WavesPlayWedge()
            .fill(tone)
            .overlay {
                WavesPlayWedge()
                    .stroke(tone, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 8.5, height: 10)
            .offset(x: 1)
    }
}

/// Simple play triangle; rounding comes from the round-join stroke overlay.
struct WavesPlayWedge: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
