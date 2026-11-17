import SwiftUI

/// Grok-style image-generation loader.
///
/// An image-card-shaped frame filled with a soft pixel/particle field that
/// drifts and twinkles as if the picture is "developing" out of noise.
/// Single horizontal scan line sweeps through to reinforce the
/// materializing feel. Minimal "Imagining…" label in the corner — no
/// progress bars, no chips, nothing else competing.
struct EmberImagineLoadingCard: View {
    let aspectRatio: CGFloat
    let title: String
    let subtitle: String
    let tint: [Color]

    init(
        aspectRatio: CGFloat = 1.0,
        title: String = "Imagining…",
        subtitle: String = "",
        tint: [Color] = [
            Color(red: 0.97, green: 0.45, blue: 0.30),
            Color(red: 0.92, green: 0.30, blue: 0.45)
        ]
    ) {
        self.aspectRatio = aspectRatio
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
    }

    @State private var t: TimeInterval = 0
    @State private var scanY: CGFloat = -0.2

    private var primary: Color { tint.first ?? .orange }
    private var secondary: Color { tint.last ?? .pink }

    /// Stable particle layout so the pixels twinkle in place rather than
    /// jittering randomly every frame.
    private static let particles: [Particle] = (0..<46).map { i in
        var r = SeededRandom(seed: UInt64(i &* 9176 &+ 1))
        return Particle(
            x: r.next(),
            y: r.next(),
            size: 1.5 + r.next() * 2.5,
            phase: r.next() * .pi * 2,
            speed: 0.6 + r.next() * 1.2
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let now = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ZStack {
                    // Calm photographic base — feels like a darkroom about
                    // to reveal something.
                    LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.09, blue: 0.11),
                            Color(red: 0.05, green: 0.05, blue: 0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // One soft tinted bloom anchoring the card's color.
                    RadialGradient(
                        colors: [
                            primary.opacity(0.32),
                            secondary.opacity(0.10),
                            .clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: max(geo.size.width, geo.size.height) * 0.7
                    )
                    .blendMode(.plusLighter)

                    // Pixel / particle field — drifts gently, twinkles.
                    Canvas { gc, size in
                        for p in Self.particles {
                            let drift = sin(now * p.speed + p.phase) * 6
                            let opacity = 0.25 + 0.55 * (0.5 + 0.5 * sin(now * 1.6 + p.phase))
                            let x = p.x * size.width + CGFloat(drift)
                            let y = p.y * size.height + CGFloat(cos(now * p.speed * 0.7 + p.phase) * 4)
                            let rect = CGRect(
                                x: x - p.size / 2,
                                y: y - p.size / 2,
                                width: p.size,
                                height: p.size
                            )
                            let color = Color.white.opacity(opacity)
                            gc.fill(Path(roundedRect: rect, cornerRadius: 0.6), with: .color(color))
                        }
                    }
                    .blendMode(.plusLighter)
                    .opacity(0.85)
                    .allowsHitTesting(false)

                    // Single soft horizontal scan band — the only sweep.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: primary.opacity(0.35), location: 0.45),
                            .init(color: .white.opacity(0.25), location: 0.5),
                            .init(color: secondary.opacity(0.35), location: 0.55),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.35)
                    .position(
                        x: geo.size.width / 2,
                        y: scanY * geo.size.height
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)

                    // Minimal corner label.
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.95))
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                            if !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(14)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(.rect(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [primary.opacity(0.45), secondary.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: primary.opacity(0.18), radius: 18, y: 8)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                scanY = 1.2
            }
        }
    }
}

private struct Particle {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let phase: Double
    let speed: Double
}

/// Tiny deterministic RNG so particle positions stay stable across renders.
private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { self.state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}

#Preview {
    VStack(spacing: 24) {
        EmberImagineLoadingCard(aspectRatio: 1)
            .frame(width: 320)
        EmberImagineLoadingCard(aspectRatio: 16.0 / 9.0)
            .frame(width: 320)
    }
    .padding()
    .background(Color(.systemBackground))
}
