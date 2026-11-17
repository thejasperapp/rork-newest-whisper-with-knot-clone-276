import SwiftUI

/// The full-screen "It's a match!" celebration — both profile pictures fly
/// in from the edges, LINK together under a heart seal, hearts drift up the
/// screen, and the names seal it. Shown once per dating thread when BOTH
/// people tap Match. Mirrors the web MatchCelebration exactly.
struct WhisperMatchCelebrationView: View {
    let myName: String
    let myAvatarURL: URL?
    let otherName: String
    let otherAvatarURL: URL?
    let onDismiss: () -> Void

    @State private var avatarsIn: Bool = false
    @State private var sealed: Bool = false
    @State private var textIn: Bool = false
    @State private var pulse: Bool = false

    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
    private let blush = Color(red: 1.0, green: 0.62, blue: 0.75)

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 0.30, green: 0.06, blue: 0.15),
                    Color(red: 0.12, green: 0.02, blue: 0.07)
                ],
                center: .center,
                startRadius: 60,
                endRadius: 520
            )
            .ignoresSafeArea()

            WhisperMatchHeartsField()
                .allowsHitTesting(false)
                .opacity(sealed ? 1 : 0)

            VStack(spacing: 0) {
                Spacer()

                // The link — two avatars overlap, sealed by the heart.
                ZStack {
                    Circle()
                        .stroke(blush.opacity(pulse ? 0 : 0.45), lineWidth: 2)
                        .frame(width: pulse ? 280 : 150, height: pulse ? 280 : 150)
                    HStack(spacing: -18) {
                        WhisperMatchAvatar(url: myAvatarURL, name: myName)
                            .offset(x: avatarsIn ? 0 : -260)
                            .rotationEffect(.degrees(avatarsIn ? -4 : -20))
                        WhisperMatchAvatar(url: otherAvatarURL, name: otherName)
                            .offset(x: avatarsIn ? 0 : 260)
                            .rotationEffect(.degrees(avatarsIn ? 4 : 20))
                    }
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            Circle().fill(
                                LinearGradient(
                                    colors: [rose, Color(red: 0.98, green: 0.45, blue: 0.62)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        )
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2.5))
                        .shadow(color: rose.opacity(0.6), radius: 12, y: 4)
                        .scaleEffect(sealed ? 1 : 0.01)
                        .offset(y: 34)
                }
                .padding(.bottom, 30)

                Text("MATCHED")
                    .font(.system(size: 11, weight: .black))
                    .tracking(3.0)
                    .foregroundStyle(blush)
                    .opacity(textIn ? 1 : 0)
                Text("It's a Match!")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 4)
                    .opacity(textIn ? 1 : 0)
                    .offset(y: textIn ? 0 : 14)
                Text("You and @\(otherName) liked each other 💘")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.horizontal, 32)
                    .opacity(textIn ? 1 : 0)
                    .offset(y: textIn ? 0 : 10)

                Spacer()

                Button {
                    Haptics.tap()
                    onDismiss()
                } label: {
                    Text("Keep chatting 💬")
                        .font(.system(size: 15.5, weight: .black))
                        .foregroundStyle(rose)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Capsule().fill(.white))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .opacity(textIn ? 1 : 0)
            }
        }
        .onAppear { runSequence() }
    }

    private func runSequence() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.72).delay(0.12)) {
            avatarsIn = true
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.58).delay(0.62)) {
            sealed = true
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.9)) {
            textIn = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(620))
            Haptics.tap()
            try? await Task.sleep(for: .milliseconds(300))
            Haptics.tap()
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

/// One profile picture in the match pair — white-ringed circle with a
/// monogram fallback so the moment lands even without a photo.
private struct WhisperMatchAvatar: View {
    let url: URL?
    let name: String

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.91, green: 0.28, blue: 0.49),
                        Color(red: 0.98, green: 0.45, blue: 0.62)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(String(name.trimmingCharacters(in: CharacterSet(charactersIn: "@")).prefix(1)).uppercased())
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            if let url {
                WhisperCachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.clear
                    }
                }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
    }
}

/// Hearts drifting up the whole screen — deterministic per-index paths so
/// the field feels alive without any randomness re-rolling on re-render.
private struct WhisperMatchHeartsField: View {
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<12, id: \.self) { i in
                WhisperMatchHeartRiser(
                    index: i,
                    width: geo.size.width,
                    height: geo.size.height
                )
            }
        }
    }
}

private struct WhisperMatchHeartRiser: View {
    let index: Int
    let width: CGFloat
    let height: CGFloat

    @State private var rise: Bool = false

    var body: some View {
        let fraction = (CGFloat(index) * 0.083 + 0.04).truncatingRemainder(dividingBy: 1.0)
        let size = 10.0 + CGFloat((index * 7) % 13)
        let duration = 3.6 + Double((index * 5) % 9) * 0.35
        let delay = Double(index) * 0.28
        let opacity = 0.14 + Double((index * 3) % 5) * 0.05
        Image(systemName: "heart.fill")
            .font(.system(size: size))
            .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.75).opacity(opacity))
            .position(x: fraction * width, y: rise ? -40 : height + 40)
            .onAppear {
                withAnimation(
                    .linear(duration: duration)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
                ) {
                    rise = true
                }
            }
    }
}
