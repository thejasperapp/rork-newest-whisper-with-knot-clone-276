import SwiftUI

/// Uses the regular DM surface for both provisional and completed answers.
/// The dots exist only while the caller owns a pending request with no text.
struct WhisperKnotReplyBubble: View {
    let text: String
    var waiting = false
    var bot: WhisperKnotBot = .main
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.whisperChatAppearance) private var appearance
    @Environment(\.whisperChatDesign) private var design
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var palette: WhisperChatPalette { design?.palette(colorScheme) ?? appearance.palette(colorScheme) }
    private var replyInk: Color { colorScheme == .dark ? .white : palette.incomingText }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Group {
                if text.isEmpty && waiting {
                    WhisperKnotReplyDots(ink: replyInk)
                        .padding(.horizontal, 3).padding(.vertical, 5)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(bot.displayName) is replying")
                } else {
                    WhisperEmberRichText(text: text, onDark: colorScheme == .dark,
                        baseSize: 16, inkOverride: replyInk, expandsHorizontally: false)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, WhisperChatStyle.bubbleHorizontal)
            .padding(.vertical, WhisperChatStyle.bubbleVertical)
            .background {
                WhisperChatStyle.shape(mine: false, isFirstInRun: true, isLastInRun: true)
                    .fill(palette.incoming)
                    .modifier(WhisperChatScrollTint(mine: false))
            }
            .animation(reduceMotion ? nil : WhisperChatStyle.spring, value: text.isEmpty)
            Spacer(minLength: 44)
        }
        .transition(reduceMotion ? .opacity : WhisperChatStyle.arrive(mine: false))
    }
}

private struct WhisperKnotReplyDots: View {
    let ink: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.whisperMediaActive) private var mediaActive
    @Environment(\.scenePhase) private var scenePhase
    @State private var began = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08,
            paused: reduceMotion || !mediaActive || scenePhase != .active)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(began)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    let pulse = reduceMotion ? 0.5 : max(0, sin(elapsed * 5 - Double(index) * 0.85))
                    Circle().fill(ink.opacity(0.3 + pulse * 0.42))
                        .frame(width: 7, height: 7)
                        .offset(y: reduceMotion ? 0 : -pulse * 2.5)
                }
            }.frame(height: 9)
        }
    }
}
