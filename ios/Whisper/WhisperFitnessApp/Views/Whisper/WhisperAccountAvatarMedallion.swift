import SwiftUI

/// A dimensional portrait, not a rotating loading coin. Readiness still belongs
/// exclusively to the account coordinator; motion never reveals account content.
struct WhisperAccountAvatarMedallion<Avatar: View>: View {
    let isReady: Bool
    let isPaused: Bool
    let avatar: Avatar
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || isReady || isPaused)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 1.35
            let tilt: Double = reduceMotion || isReady || isPaused ? 0 : sin(phase) * 8
            ZStack {
                Ellipse().fill(.black.opacity(scheme == .dark ? 0.35 : 0.13))
                    .frame(width: 106, height: 16).blur(radius: 10).offset(y: 82)
                ZStack {
                    Circle().fill(WhisperBrandGradient.accent.opacity(0.24)).frame(width: 130, height: 130).offset(x: 3, y: 8)
                    Circle().fill(LinearGradient(colors: [.white.opacity(0.8), WhisperBrandGradient.amber.opacity(0.65), WhisperBrandGradient.accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 128, height: 128)
                    avatar
                        .overlay {
                            Circle().fill(LinearGradient(stops: [.init(color: .white.opacity(0.25), location: 0), .init(color: .clear, location: 0.48), .init(color: .black.opacity(0.14), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.08), .black.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5).frame(width: 128, height: 128)
                }
                .rotation3DEffect(.degrees(tilt), axis: (x: 0.4, y: 1, z: 0), perspective: 0.5)
                .offset(y: reduceMotion || isReady || isPaused ? 0 : cos(phase) * 3)
                .shadow(color: WhisperBrandGradient.accent.opacity(0.12), radius: 22, x: 0, y: 14)
            }
            .frame(width: 160, height: 176)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isReady)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
