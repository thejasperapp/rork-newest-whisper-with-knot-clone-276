import SwiftUI

// MARK: - Instagram story design kit
//
// Shared visual language for the story system, matched to the Instagram
// UI Kit: the iconic conic gradient ring, the viewer reply bar ("Send
// message" + heart + share), the quick emoji reactions, the floating
// reaction burst, and the "Seen by" facepile for your own stories.

/// The Whisper story ring gradient — the green identity: ghost mint →
/// emerald → deep mint → forest, wrapped back to mint so the conic sweep
/// has no seam. Matches `WHISPER_STORY_RING` on web 1:1.
enum WhisperIGRing {
    static let colors: [Color] = [
        Color(red: 0.608, green: 0.910, blue: 0.769), // #9BE8C4
        Color(red: 0.204, green: 0.827, blue: 0.600), // #34D399
        Color(red: 0.055, green: 0.624, blue: 0.463), // #0E9F76
        Color(red: 0.016, green: 0.471, blue: 0.341), // #047857
        Color(red: 0.169, green: 0.831, blue: 0.541), // #2BD48A
        Color(red: 0.608, green: 0.910, blue: 0.769)  // wrap
    ]

    static var gradient: AngularGradient {
        AngularGradient(colors: colors, center: .center, angle: .degrees(210))
    }

    /// Flat linear version for text fills (hashtag sticker, accents).
    static var linear: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.016, green: 0.471, blue: 0.341), // #047857
                Color(red: 0.055, green: 0.624, blue: 0.463), // #0E9F76
                Color(red: 0.204, green: 0.827, blue: 0.600)  // #34D399
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Short Instagram-style age for a story timestamp — "now", "5m", "2h", "1d".
func whisperStoryTimeAgo(_ iso: String?) -> String {
    guard let iso else { return "" }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = f.date(from: iso)
    if date == nil {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        date = plain.date(from: iso)
    }
    guard let date else { return "" }
    let s = max(0, Date().timeIntervalSince(date))
    if s < 60 { return "now" }
    if s < 3600 { return "\(Int(s / 60))m" }
    if s < 86_400 { return "\(Int(s / 3600))h" }
    return "\(Int(s / 86_400))d"
}

/// The eight Instagram quick reactions, in kit order.
let whisperStoryQuickReactions: [String] = ["❤️", "🙌", "😂", "😮", "😢", "🔥", "🎉", "💯"]

/// Instagram-style reply bar pinned to the bottom of someone else's story:
/// a stroked "Send message" field, the like heart, and the share plane.
struct WhisperStoryReplyBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let liked: Bool
    let sending: Bool
    let onShare: () -> Void
    let onSend: () -> Void
    let onLike: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField(
                    "",
                    text: $text,
                    prompt: Text("Send message").foregroundStyle(.white.opacity(0.75))
                )
                .focused(focused)
                .font(.subheadline)
                .foregroundStyle(.white)
                .tint(.white)
                .submitLabel(.send)
                .onSubmit { onSend() }
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        Haptics.tap()
                        onSend()
                    } label: {
                        if sending {
                            ProgressView().tint(.white)
                        } else {
                            Text("Send")
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(
                Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1)
            )
            .contentShape(Capsule())

            Button {
                Haptics.tap()
                onLike()
            } label: {
                WhisperRoundedGlyph(kind: .heart, selected: liked)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(liked ? Color(red: 0.93, green: 0.16, blue: 0.30) : .white)
                    .scaleEffect(liked ? 1.08 : 1)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55), value: liked)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(liked ? "Unlike story" : "Like story")

            Button(action: onShare) {
                WhisperRoundedGlyph(kind: .share).frame(width: 24, height: 24)
                    .foregroundStyle(.white).frame(width: 44, height: 44).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(sending)
            .accessibilityLabel("Send Story in a message")
        }
        .padding(.horizontal, 14)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: text.isEmpty)
    }
}

/// The 2×4 quick-reaction grid shown while the reply field is focused —
/// tap an emoji to send it instantly as a DM reaction.
struct WhisperStoryQuickReactionsGrid: View {
    let onPick: (String) -> Void

    var body: some View {
        VStack(spacing: 26) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { col in
                        let emoji = whisperStoryQuickReactions[row * 4 + col]
                        Button {
                            Haptics.success()
                            onPick(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 42))
                                .frame(maxWidth: .infinity)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

/// Floating emoji burst — six copies of the reaction drift up and fade,
/// Instagram-style, after a like or quick reaction.
struct WhisperStoryReactionBurst: View {
    let emoji: String
    /// Changing the trigger re-seeds and replays the burst.
    let trigger: Int
    @State private var animate: Bool = false

    private var seeds: [(x: CGFloat, delay: Double, size: CGFloat)] {
        var gen = SeededRandom(seed: UInt64(max(1, trigger)))
        return (0..<6).map { _ in
            (
                x: CGFloat(gen.next(in: -110...110)),
                delay: Double(gen.next(in: 0...0.25)),
                size: CGFloat(gen.next(in: 30...52))
            )
        }
    }

    var body: some View {
        ZStack {
            ForEach(Array(seeds.enumerated()), id: \.offset) { _, seed in
                Text(emoji)
                    .font(.system(size: seed.size))
                    .offset(x: seed.x, y: animate ? -420 : 40)
                    .opacity(animate ? 0 : 1)
                    .scaleEffect(animate ? 1.25 : 0.6)
                    .animation(
                        .easeOut(duration: 1.15).delay(seed.delay),
                        value: animate
                    )
            }
        }
        .allowsHitTesting(false)
        .onAppear { animate = true }
        .id(trigger)
        .onChange(of: trigger) { _, _ in
            animate = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                animate = true
            }
        }
    }
}

/// Tiny deterministic random source so burst layouts differ per trigger
/// without pulling in GameplayKit.
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let unit = Double(state >> 11) / Double(UInt64.max >> 11)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

/// "Seen by N" facepile for your own story — overlapping viewer avatars
/// plus the count; tapping opens the full viewers sheet.
struct WhisperStorySeenByFacepile: View {
    let viewers: [WhisperStoryViewRow]
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 8) {
                if viewers.isEmpty {
                    Image(systemName: "eye.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    HStack(spacing: -9) {
                        ForEach(Array(viewers.prefix(3).enumerated()), id: \.offset) { _, v in
                            WhisperAvatar(username: v.viewer_username, size: 26, ring: false)
                                .overlay(Circle().strokeBorder(.black.opacity(0.85), lineWidth: 1.6))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(count == 1 ? "Seen by 1" : "Seen by \(count)")
                        .font(.caption.weight(.bold))
                        .contentTransition(.numericText(value: Double(count)))
                }
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Seen by \(count) — open viewers")
    }
}
