import SwiftUI

/// Interlocked, overlapping profile photos for group lives — the Instagram
/// treatment where 2-4 broadcasters share one bubble. Each face gets a thin
/// surface-colored ring so the circles read as interlocked, not smeared.
///
/// Used in the story-row live bubbles, the live room top bar, and the live
/// rooms list cards.
struct WhisperLiveAvatarCluster: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Up to 4 user IDs, host first.
    let userIDs: [String]
    /// Hydrated profiles keyed by userID — supplies username + photo.
    var profiles: [String: WhisperBackendService.WhisperPublicProfile] = [:]
    /// Outer diameter of the whole cluster.
    var size: CGFloat = 64
    /// Ring color drawn around each face so overlaps stay crisp.
    var ringColor: Color? = nil

    private var ids: [String] { Array(userIDs.prefix(4)) }

    private func username(for id: String) -> String {
        profiles[id]?.username ?? profiles[id]?.display_name ?? id
    }

    private func imageURL(for id: String) -> URL? {
        guard let s = profiles[id]?.profile_image_url else { return nil }
        return URL(string: s)
    }

    private var border: Color {
        ringColor ?? WhisperTheme.surface(colorScheme)
    }

    var body: some View {
        ZStack {
            switch ids.count {
            case 0:
                Circle()
                    .fill(WhisperTheme.card(colorScheme))
                    .frame(width: size, height: size)
            case 1:
                face(ids[0], diameter: size)
            case 2:
                face(ids[1], diameter: size * 0.66)
                    .offset(x: size * 0.17, y: size * 0.17)
                face(ids[0], diameter: size * 0.66)
                    .offset(x: -size * 0.17, y: -size * 0.17)
            case 3:
                face(ids[1], diameter: size * 0.55)
                    .offset(x: -size * 0.21, y: size * 0.19)
                face(ids[2], diameter: size * 0.55)
                    .offset(x: size * 0.21, y: size * 0.19)
                face(ids[0], diameter: size * 0.55)
                    .offset(y: -size * 0.21)
            default:
                face(ids[3], diameter: size * 0.52)
                    .offset(x: size * 0.19, y: size * 0.19)
                face(ids[2], diameter: size * 0.52)
                    .offset(x: -size * 0.19, y: size * 0.19)
                face(ids[1], diameter: size * 0.52)
                    .offset(x: size * 0.19, y: -size * 0.19)
                face(ids[0], diameter: size * 0.52)
                    .offset(x: -size * 0.19, y: -size * 0.19)
            }
        }
        .frame(width: size, height: size)
    }

    private func face(_ id: String, diameter: CGFloat) -> some View {
        WhisperAvatar(
            username: username(for: id),
            size: diameter,
            imageURL: imageURL(for: id)
        )
        .overlay {
            Circle().strokeBorder(border, lineWidth: max(1.5, diameter * 0.045))
        }
    }
}

/// Animated red gradient ring for live bubbles — slowly rotating angular
/// gradient with a soft pulse, Instagram-style.
struct WhisperLiveRing: View {
    var size: CGFloat
    var lineWidth: CGFloat = 2.5
    /// Amber for upcoming/scheduled lives, red for live.
    var isUpcoming: Bool = false

    @State private var spin = false

    private var colors: [Color] {
        if isUpcoming {
            return [Color.orange, Color.yellow.opacity(0.8), Color.orange]
        }
        return [
            Color(red: 0.95, green: 0.15, blue: 0.35),
            Color(red: 1.0, green: 0.45, blue: 0.25),
            Color(red: 0.85, green: 0.1, blue: 0.55),
            Color(red: 0.95, green: 0.15, blue: 0.35)
        ]
    }

    var body: some View {
        Circle()
            .strokeBorder(
                AngularGradient(colors: colors, center: .center),
                lineWidth: lineWidth
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    spin = true
                }
            }
    }
}
