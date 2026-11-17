import SwiftUI

// MARK: - The long-press moment
//
// Long-pressing a bubble never opens a sheet. The thread blurs heavily and
// washes out in place, the pressed bubble stays exactly where it was (a
// whisper of lift), a FULL-WIDTH white reaction strip settles in above it,
// and a tall, quiet actions card settles in below on the bubble's side — the
// reference structure exactly:
//
//   ┌──────────────────────────────────────────────┐
//   │  ❤️     😂     😮     😢     😡     👍     +   │   ← full-width strip
//   └──────────────────────────────────────────────┘
//                              ┌────────────────────┐
//                              │  the bubble         │
//                              └────────────────────┘
//                              ┌──────────────┐
//                              │ 5:33 PM       │
//                              │ ↩  Reply      │
//                              │ ✈  Forward    │
//                              │ ⧉  Copy       │
//                              │ 🗑  Delete…    │
//                              │ ⟲  Unsend     │   (red)
//                              │ …  More     › │
//                              └──────────────┘
//
// Every frame is measured in GLOBAL coordinates (the capture and the overlay
// agree even though the overlay ignores the safe area), so nothing jumps.

/// What the overlay needs to know about the pressed message.
struct WhisperMessagePressContext {
    let messageID: String
    let mine: Bool
    /// The bubble's frame in GLOBAL (screen) coordinates.
    let frame: CGRect
    /// "5:33 PM" — the card's header.
    let timeLabel: String
    let selectedReaction: String?
}

/// One row in the press card.
struct WhisperMessagePressAction: Identifiable {
    let id: String
    let icon: String
    let title: String
    var isDestructive: Bool = false
    /// "More ›" style — trailing chevron.
    var hasChevron: Bool = false
    let handler: () -> Void
}

/// The overlay itself. Rendered by the thread over its blurred content.
struct WhisperMessagePressOverlay<Bubble: View>: View {
    let context: WhisperMessagePressContext
    let reactions: [String]
    let actions: [WhisperMessagePressAction]
    let onReaction: (String) -> Void
    let onDismiss: () -> Void
    @ViewBuilder let bubble: () -> Bubble

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false
    /// The emojis ride their own flag so they can wave in one after another
    /// (staggered springs) and leave together.
    @State private var emojisShown: Bool = false
    @State private var pickerExpanded: Bool = false
    @State private var poppedEmoji: String?
    @State private var releasing: Bool = false
    @State private var ownerGeneration: UUID = AccountStorage.generation

    // The reference metrics (points).
    private let stripHeight: CGFloat = 54
    private let stripMargin: CGFloat = 18
    private let expandedRows: CGFloat = 84
    private let gapAbove: CGFloat = 16
    private let gapBelow: CGFloat = 14
    private let cardWidth: CGFloat = 186
    private let rowHeight: CGFloat = 50
    private let cardHeaderHeight: CGFloat = 40
    private let cardBottomPad: CGFloat = 6
    private let edge: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let origin: CGPoint = geo.frame(in: .global).origin
            let size: CGSize = geo.size
            // The bubble's frame in THIS view's coordinates.
            let local = CGRect(
                x: context.frame.minX - origin.x,
                y: context.frame.minY - origin.y,
                width: context.frame.width,
                height: context.frame.height
            )
            let layout: Layout = layout(bubble: local, in: size, safeTop: geo.safeAreaInsets.top, safeBottom: geo.safeAreaInsets.bottom)
            ZStack(alignment: .topLeading) {
                // The wash — a tap anywhere lets go.
                scrim
                    .opacity(shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: shown)
                    .contentShape(.rect)
                    .onTapGesture { release() }

                // The bubble — same content, same width, exactly where it was
                // (it only travels when it must to make room), a whisper of lift.
                bubble()
                    .frame(width: local.width, height: local.height)
                    .frame(height: layout.previewHeight, alignment: .top)
                    .clipped()
                    .shadow(color: .black.opacity(shown ? 0.10 : 0), radius: 14, y: 6)
                    .offset(x: local.minX, y: shown ? layout.bubbleY : local.minY)
                    .animation(.smooth(duration: reduceMotion ? 0 : 0.2), value: shown)
                    .allowsHitTesting(false)

                // The reaction strip — full width, above the bubble. It settles
                // in from the bubble's corner with a touch of spring while the
                // emojis inside wave in one after another.
                reactionStrip
                    .frame(width: size.width - stripMargin * 2)
                    .offset(x: stripMargin, y: layout.stripY)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.97, anchor: context.mine ? .bottomTrailing : .bottomLeading)
                    .offset(y: shown || reduceMotion ? 0 : 4)
                    .opacity(shown ? 1 : 0)
                    .animation(.smooth(duration: reduceMotion ? 0 : 0.22), value: shown)

                // The actions card — below the bubble, on the bubble's side,
                // a beat behind the strip so the moment reads top-down.
                ScrollView { actionsCard }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: cardWidth, height: layout.actionsHeight)
                    .background(cardFill, in: .rect(cornerRadius: WhisperMenuGeometry.cardRadius, style: .continuous))
                    .clipShape(.rect(cornerRadius: WhisperMenuGeometry.cardRadius, style: .continuous))
                    .offset(x: layout.cardX, y: layout.cardY)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.97, anchor: context.mine ? .topTrailing : .topLeading)
                    .offset(y: shown || reduceMotion ? 0 : -4)
                    .opacity(shown ? 1 : 0)
                    .animation(.smooth(duration: reduceMotion ? 0 : 0.22), value: shown)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            Haptics.soft()
            shown = true
            emojisShown = true
        }
    }

    /// The reference wash: the blurred thread reads pale and quiet in light
    /// mode, deep in dark mode — never a heavy black scrim over a light chat.
    private var scrim: some View {
        ZStack {
            // A system material blurs the thread on the GPU — animating a
            // 26pt Gaussian blur over the live message list was the lag on
            // every press. The thread underneath never changes now.
            Rectangle().fill(.regularMaterial)
            (colorScheme == .dark ? Color.black.opacity(0.28) : WhisperTheme.surface(colorScheme).opacity(0.42))
        }
        .ignoresSafeArea()
    }

    // MARK: Layout

    private struct Layout {
        let bubbleY: CGFloat
        let stripY: CGFloat
        let cardY: CGFloat
        let cardX: CGFloat
        let previewHeight: CGFloat
        let actionsHeight: CGFloat
    }

    private var cardHeight: CGFloat {
        cardHeaderHeight + CGFloat(actions.count) * rowHeight + cardBottomPad
    }

    private var stripBlock: CGFloat {
        pickerExpanded ? stripHeight + expandedRows : stripHeight
    }

    private func layout(bubble local: CGRect, in size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) -> Layout {
        let top: CGFloat = safeTop + 10
        let bottom: CGFloat = size.height - safeBottom - 12
        let room = max(0, bottom - top - stripBlock - gapAbove - gapBelow)
        let actionsH = min(cardHeight, room * 0.65)
        let bubbleH = min(local.height, max(0, room - actionsH))
        let minBubbleY: CGFloat = top + stripBlock + gapAbove
        let maxBubbleY: CGFloat = bottom - actionsH - gapBelow - bubbleH
        var y: CGFloat = local.minY
        if maxBubbleY >= minBubbleY {
            // Stay put whenever everything fits; otherwise travel the
            // shortest distance that makes room.
            y = min(max(y, minBubbleY), maxBubbleY)
        } else {
            // A bubble taller than the room we have — keep its top visible
            // under the strip; the card will sit as high as it can.
            y = minBubbleY
        }
        let rawCardX: CGFloat = context.mine ? local.maxX - cardWidth : local.minX
        let cardX: CGFloat = min(max(edge, rawCardX), size.width - cardWidth - edge)
        return Layout(
            bubbleY: y,
            stripY: y - gapAbove - stripBlock,
            cardY: y + bubbleH + gapBelow,
            cardX: cardX,
            previewHeight: bubbleH,
            actionsHeight: actionsH
        )
    }

    // MARK: Reaction strip

    private var stripFill: Color {
        colorScheme == .dark ? WhisperTheme.card(colorScheme) : WhisperTheme.surface(colorScheme)
    }

    /// The wave: each emoji springs up from small with a little overshoot,
    /// one 35 ms after the last, then settles — the "+" rides in last. On the
    /// way out they leave together (no stagger).
    private func waveIn<V: View>(_ view: V, index: Int) -> some View {
        view
            .scaleEffect(emojisShown || reduceMotion ? 1 : 0.92)
            .offset(y: emojisShown || reduceMotion ? 0 : 4)
            .opacity(emojisShown ? 1 : 0)
            .animation(
                .smooth(duration: reduceMotion ? 0 : 0.2),
                value: emojisShown
            )
    }

    private var reactionStrip: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(reactions.enumerated()), id: \.element) { i, emoji in
                    waveIn(reactionButton(emoji, size: 30), index: i)
                        .frame(maxWidth: .infinity)
                }
                waveIn(
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            pickerExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: pickerExpanded ? "chevron.up" : "plus")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.85))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pickerExpanded ? "Fewer reactions" : "More reactions"),
                    index: reactions.count
                )
                .frame(maxWidth: .infinity)
            }
            .frame(height: stripHeight)
            if pickerExpanded {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 8), spacing: 4) {
                    ForEach(WhisperMessagePressEmojis.more, id: \.self) { emoji in
                        reactionButton(emoji, size: 24)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(stripFill, in: RoundedRectangle(cornerRadius: pickerExpanded ? 26 : 27, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.10), radius: 18, y: 6)
    }

    private func reactionButton(_ emoji: String, size: CGFloat) -> some View {
        let selected = context.selectedReaction == emoji
        return Button {
            guard !releasing, poppedEmoji == nil, ownerGeneration == AccountStorage.generation else { return }
            Haptics.soft()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { poppedEmoji = emoji }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard ownerGeneration == AccountStorage.generation else { return }
                onReaction(emoji)
                release()
            }
        } label: {
            Text(emoji)
                .font(.system(size: size))
                .frame(width: size + 14, height: size + 14)
                .background {
                    if selected {
                        Circle().fill(WhisperTheme.ink(colorScheme).opacity(colorScheme == .dark ? 0.22 : 0.08))
                    }
                }
                .scaleEffect(poppedEmoji == emoji ? 1.4 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(WhisperEmojiPressStyle())
        .accessibilityLabel("React \(emoji)")
    }

    // MARK: Actions card

    private var cardFill: Color {
        colorScheme == .dark ? Color(white: 0.13) : WhisperTheme.card(colorScheme)
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(context.timeLabel)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 18)
                .frame(height: cardHeaderHeight, alignment: .bottomLeading)
                .padding(.bottom, 0)
            ForEach(actions) { action in
                Button {
                    guard !releasing, ownerGeneration == AccountStorage.generation else { return }
                    if action.isDestructive { Haptics.warning() } else { Haptics.tap() }
                    release()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        guard ownerGeneration == AccountStorage.generation else { return }
                        action.handler()
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: action.icon)
                            .font(.system(size: 20, weight: .regular))
                            .frame(width: 26)
                        Text(action.title)
                            .font(.system(size: 16, weight: .regular))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if action.hasChevron {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.75))
                        }
                    }
                    .foregroundStyle(action.isDestructive ? Color(red: 0.93, green: 0.22, blue: 0.22) : WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 18)
                    .frame(height: rowHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(WhisperMenuPressStyle())
            }
        }
        .padding(.bottom, cardBottomPad)
        .frame(height: cardHeight)
        .background(cardFill, in: RoundedRectangle(cornerRadius: WhisperMenuGeometry.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.08), radius: 20, y: 8)
    }

    // MARK: Release

    private func release() {
        guard !releasing else { return }
        releasing = true
        shown = false
        emojisShown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
    }
}

/// Emoji buttons grow a touch under the finger and snap back — the strip
/// answers every touch before the reaction even fires.
struct WhisperEmojiPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.22 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Emojis behind the "+" — the second row of the reaction strip.
enum WhisperMessagePressEmojis {
    static let more: [String] = ["🔥", "🙌", "💯", "🎉", "😍", "🤔", "👀", "🙏", "😭", "🥹", "💀", "👏", "🫶", "😤", "🤝", "✨"]
}

/// Wraps message content and hands its GLOBAL frame to the caller exactly
/// once when `armed` flips to this message — zero cost for every other bubble
/// (the geometry reader only mounts while armed). Global coordinates mean the
/// overlay (which ignores the safe area) and the thread (which doesn't) agree.
struct WhisperFrameCapture: ViewModifier {
    let armed: Bool
    let onCapture: (CGRect) -> Void

    func body(content: Content) -> some View {
        content.background {
            if armed {
                GeometryReader { geo in
                    Color.clear.onAppear {
                        onCapture(geo.frame(in: .global))
                    }
                }
            }
        }
    }
}

extension View {
    /// See `WhisperFrameCapture`.
    func whisperCaptureFrame(armed: Bool, onCapture: @escaping (CGRect) -> Void) -> some View {
        modifier(WhisperFrameCapture(armed: armed, onCapture: onCapture))
    }
}
