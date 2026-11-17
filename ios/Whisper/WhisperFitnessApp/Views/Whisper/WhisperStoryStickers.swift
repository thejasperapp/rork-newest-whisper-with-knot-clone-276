import Foundation
import SwiftUI
import AVFoundation
import AVKit

/// Interactive overlays that can be dragged, scaled, and rotated on top of a
/// story photo — text labels, polls, sliders, ask-me questions, location pills,
/// @mentions, music chips, and animated GIF stickers. Each carries a position
/// in normalized (0…1) coordinates so the same payload renders consistently
/// across screen sizes between composer and viewer.
nonisolated struct WhisperStorySticker: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text
        case poll
        case slider
        case question
        case location
        case mention
        case music
        case gif
        case sticker
        case photo
        case hashtag
        case countdown
        /// A shared wave (short video) — Instagram's "Add reel to your
        /// story" card: cover + author + a Watch pill; tap opens the wave.
        case wave
        /// A shared grid POST — Instagram's "Add post to your story" card:
        /// the post's cover with the author row on top and the caption line
        /// under it; tap opens the post. Identical wire on web (`post`).
        case post
    }

    var id: String = UUID().uuidString
    var kind: Kind
    /// Normalized centre (0…1) on the canvas.
    var x: Double = 0.5
    var y: Double = 0.5
    var scale: Double = 1.0
    var rotation: Double = 0

    // Text / question
    var text: String?
    /// Hex color (e.g. "#FFFFFF") for the text fill.
    var color: String?
    /// Hex color (e.g. "#000000") for the background pill, optional.
    var background: String?
    /// 0 = no background, 1 = solid pill, 2 = outline.
    var style: Int?

    // Poll
    var pollOptions: [String]?

    // Slider
    var sliderEmoji: String?

    // Music
    var musicTitle: String?
    var musicArtist: String?
    var musicArtwork: String?

    // Location / mention
    var label: String?
    /// Pinned latitude for `.location` stickers — captured the moment the
    /// author tapped "Add place" so the pin stays exact even after they
    /// rename the visible label.
    var latitude: Double?
    /// Pinned longitude. See `latitude`.
    var longitude: Double?

    // GIF / animated sticker / photo cover
    var imageURL: String?
    /// Optional sizing for new shared cards; older stories keep their original geometry.
    var mediaAspectRatio: Double?
    var cardWidthFraction: Double?
    var mediaCount: Int?

    /// Photo sticker mask — `rect` (default) · `circle` · `heart` · `star`
    /// · `squircle`. Tapping a photo sticker in the editor cycles through
    /// them, Instagram-style. Rendered identically on web via clip-path.
    var shape: String?

    /// `.wave` — the shared post's id (lowercase uuid) so the viewer can
    /// open the original wave on tap.
    var postID: String?
    /// `.wave` — the wave's video URL (plays muted + looped inside the card).
    var videoURL: String?

    // Question response (baked-in answer for IG-style Q&A re-share). When
    // non-nil on a `.question` sticker, the card renders the answer inside
    // the bubble in place of the "Type something…" placeholder, captioned
    // with the responder's handle below.
    var answer: String?
    var responderUsername: String?
    var fontName: String?
    var fontSize: Double?
    var textAlignment: String?
    var photoFrame: Bool?
    /// Optional presentation on ordinary photo layers; legacy frames remain unchanged.
    var photoLayout: String?
    var frameTimestamp: String?
    /// Presentation only, never an access-control boundary.
    var frameReveal: Bool?

    var isPhotoCard: Bool { kind == .photo && (photoLayout == "frame" || photoLayout == "strip") }
    var isRevealFrame: Bool { kind == .photo && photoLayout == "frame" && frameReveal == true }
    /// Kept on a text sticker so older clients still display its label.
    var linkURL: String?
}

nonisolated struct WhisperStoryMetadata: Codable, Sendable {
    var stickers: [WhisperStorySticker] = []
    var musicSelection: WhisperStoryMusicSelection? = nil
    /// Logical width used when composing fixed-size stickers; absent on legacy stories.
    var referenceStageWidth: Double? = nil
}

extension WhisperStoryMetadata {
    /// JSON-encoded string for the `metadata` column. `nil` if empty.
    var jsonString: String? {
        guard !stickers.isEmpty || musicSelection != nil else { return nil }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ raw: String?) -> WhisperStoryMetadata {
        guard let raw, let data = raw.data(using: .utf8) else { return .init() }
        return (try? JSONDecoder().decode(WhisperStoryMetadata.self, from: data)) ?? .init()
    }
}

// MARK: - Rendering

/// Renders a single sticker on either the editor canvas (interactive) or the
/// viewer canvas (read-only / vote-able).
struct WhisperStoryStickerView: View {
    let sticker: WhisperStorySticker
    var stageWidth: CGFloat = 390
    var authoring: WhisperStoryStickerAuthoring? = nil
    var isInteractive: Bool = false
    var frameRevealed: Bool = true
    var onPhotoCardReady: (() -> Void)? = nil
    var onVote: ((Int) -> Void)? = nil
    var onSlider: ((Double) -> Void)? = nil
    /// When provided, the poll body defers commit to the parent: tapping
    /// an option just updates this binding (no auto-vote, no internal
    /// "Sent!" toast). The parent renders an external Send pill that
    /// fires the commit — same lifted+blurred pattern as the question card.
    var pendingPollSelection: Binding<Int?>? = nil
    /// Same idea for the slider: dragging updates this binding but the
    /// slider never auto-commits. The parent renders the Send pill.
    var pendingSliderValue: Binding<Double?>? = nil
    /// When non-nil on a poll, the card switches from option-buttons to
    /// horizontal percentage-bar results. Each entry is the vote count for
    /// the option at that index.
    var pollTally: [Int]? = nil
    /// Index the viewer picked — shown highlighted in the results view.
    var votedIndex: Int? = nil
    /// Fires the first time the viewer touches an interactive poll/slider.
    /// Used by the parent to flip into the lifted/blurred editing state.
    var onBeginInteract: (() -> Void)? = nil
    /// Fired when the whole sticker is tapped (question, mention,
    /// location). Used by the story viewer to open a response sheet or
    /// navigate to the mentioned user.
    var onTap: (() -> Void)? = nil
    /// When non-nil and the sticker is a question, the card renders an
    /// inline TextField bound to this string instead of the static
    /// "Type something…" placeholder — so the viewer types directly on
    /// the actual question card the author drew, not a separate sheet.
    var editableQuestionText: Binding<String>? = nil
    /// Fired when the viewer taps the send glyph on an editable question
    /// card. Only invoked when `editableQuestionText` is bound.
    var onSubmitQuestion: (() -> Void)? = nil
    /// Optional focus binding the parent can flip to pop the keyboard
    /// the moment the question card becomes editable.
    var questionFieldFocused: FocusState<Bool>.Binding? = nil
    /// Username of the user who *authored* this sticker (the story poster).
    /// When provided, the question card renders the poster's avatar floating
    /// above the top edge of the card — matching the Instagram "ask me
    /// anything" reference. The avatar auto-resolves its image URL from the
    /// backend's avatar cache via `WhisperAvatar`, so callers only need to
    /// pass the handle.

    var body: some View {
        switch sticker.kind {
        case .text:
            if sticker.linkURL != nil { tappableWrap(pillCard(icon: "link", text: sticker.text ?? "Open link")) }
            else { WhisperStoryStickerText(sticker: sticker, authoring: authoring) }
        case .question:
            if editableQuestionText != nil {
                editableQuestionCard
            } else {
                tappableWrap(questionCard)
            }
        case .poll:
            pollCard
        case .slider:
            if sticker.style == 9 {
                Button {
                    guard isInteractive else { return }
                    onBeginInteract?()
                    if let selection = pendingSliderValue { selection.wrappedValue = 1 }
                    else { onSlider?(1) }
                } label: {
                    Text(sticker.sliderEmoji ?? "\u{1F60D}").font(.system(size: 46)).frame(width: 88, height: 88)
                        .background(cardBackgroundColor, in: .circle)
                }.buttonStyle(.plain).disabled(!isInteractive).accessibilityLabel("React to this story")
            } else { sliderCard }
        case .location:
            tappableWrap(locationCard)
        case .mention:
            tappableWrap(pillCard(icon: "at", text: sticker.label ?? ""))
        case .music:
            musicChip
        case .gif, .sticker:
            gifThumb
        case .photo:
            if sticker.isPhotoCard {
                WhisperStoryPhotoCardView(sticker: sticker, stageWidth: stageWidth, isRevealed: frameRevealed, onReveal: isInteractive ? onTap : nil, onMediaReady: onPhotoCardReady)
            } else { photoThumb }
        case .hashtag:
            hashtagCard
        case .countdown:
            countdownCard
        case .wave:
            seePostWrap(waveCard, label: "Watch wave")
        case .post:
            seePostWrap(postCard, label: "See post")
        }
    }

    /// Instagram's shared-post grammar (the reference screenshots): the
    /// post's PICTURE is the card — rounded corners, no white frame, no author
    /// row — with the small white "post" glyph in its top-right corner and
    /// the author's @handle credited BENEATH the card. Text-only posts render
    /// as a quiet ink card carrying the author row + the words.
    private var postCard: some View {
        let cardSize = WhisperStoryPostCardLayout.size(sticker: sticker, stageWidth: stageWidth)
        return VStack(alignment: .leading, spacing: 10) {
            if let urlStr = sticker.imageURL, let url = URL(string: urlStr) {
                ZStack(alignment: .topTrailing) {
                    Color(white: 0.12)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .overlay {
                            WhisperCachedAsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(contentMode: sticker.mediaAspectRatio == nil ? .fill : .fit)
                                default:
                                    LinearGradient(colors: [Color(white: 0.22), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                                }
                            }
                            .allowsHitTesting(false)
                        }
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                    sharedPostGlyph
                        .padding(10)
                }
            } else {
                // Text post: the words ARE the picture.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        WhisperAvatar(username: sticker.label ?? "", size: 26, ring: false)
                        Text(sticker.label ?? "")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        sharedPostGlyph
                    }
                    Text(sticker.text ?? "")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(8)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(width: 250, alignment: .leading)
                .background(Color(white: 0.09).opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.75)
                }
            }

            // The credit beneath the card — "@joyymeek" in the reference.
            Text("@\(sticker.label ?? "")")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                .padding(.leading, 4)
        }
        .frame(width: sticker.imageURL == nil ? 250 : cardSize.width, alignment: .leading)
        .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
    }

    /// Instagram's shared-post glyph: a small white rounded square with a
    /// notch — the badge that marks "this is a post" on the card's corner.
    private var sharedPostGlyph: some View {
        Image(systemName: (sticker.mediaCount ?? 1) > 1 ? "square.on.square.fill" : "square.fill")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(.white)
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    /// Instagram's two-tap grammar for shared posts and waves: the FIRST tap
    /// arms a "See post ›" pill on the card (auto-disarms after a beat); the
    /// pill's tap opens the original. Non-interactive contexts render as-is.
    @ViewBuilder
    private func seePostWrap<Content: View>(_ content: Content, label: String) -> some View {
        if isInteractive, let onTap {
            WhisperStorySeePostWrap(label: label, onOpen: onTap) { content }
        } else {
            content
        }
    }

    /// Instagram's "Add reel to your story" card — a 9:16 rounded card with
    /// the wave's cover (or a muted looping preview), the author row under
    /// it, and the "Watch wave" pill the viewer taps to open the original.
    private var waveCard: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let urlStr = sticker.imageURL, let url = URL(string: urlStr) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            LinearGradient(colors: [Color(white: 0.18), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
                        }
                    }
                }
                if let v = sticker.videoURL, let url = URL(string: v), isInteractive {
                    WhisperStoryWaveLoopView(url: url)
                        .allowsHitTesting(false)
                }
                LinearGradient(colors: [.clear, .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "play.rectangle.on.rectangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .padding(10)
                    }
                    Spacer()
                    if !isInteractive || sticker.videoURL == nil {
                        Image(systemName: "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.5), radius: 8)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .black))
                        Text("Watch wave")
                            .font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(.white, in: Capsule())
                    .padding(.bottom, 12)
                }
            }
            .frame(width: 186, height: 330)
            .clipShape(.rect(cornerRadius: 18))

            HStack(spacing: 7) {
                WhisperAvatar(username: sticker.label ?? "", size: 22, ring: false)
                Text("@\(sticker.label ?? "")")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let cap = sticker.text, !cap.isEmpty {
                    Text("· \(cap)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(.top, 8)
            .frame(width: 186, alignment: .leading)
        }
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    /// Instagram hashtag sticker — a white pill with the tag in the
    /// gradient wordmark colors.
    private var hashtagCard: some View {
        Text("#\((sticker.label ?? "").uppercased())")
            .font(.system(size: 24, weight: .heavy))
            .foregroundStyle(WhisperIGRing.linear)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    /// Instagram countdown sticker — a white card with the event title
    /// and a live remaining clock that ticks while the story plays.
    private var countdownCard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 5) {
                Group {
                    if let authoring {
                        TextField("COUNTDOWN NAME", text: authoring.text, axis: .vertical)
                            .focused(authoring.focus).tint(cardForegroundColor).multilineTextAlignment(.center)
                    } else { Text((sticker.label ?? "Countdown").uppercased()) }
                }
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(cardForegroundColor.opacity(0.55))
                    .lineLimit(1)
                if let choose = authoring?.chooseDeadline {
                    Button(action: choose) {
                        Text(countdownRemaining(at: context.date))
                            .font(.system(size: 30, weight: .light, design: .monospaced)).monospacedDigit()
                            .frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(cardForegroundColor)
                        .accessibilityLabel("Set countdown end date and time")
                } else {
                    Text(countdownRemaining(at: context.date))
                        .font(.system(size: 30, weight: .light, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(cardForegroundColor)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(width: 240)
            .background(cardBackgroundColor, in: .rect(cornerRadius: 12))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
    }

    private func countdownRemaining(at now: Date) -> String {
        guard let iso = sticker.text else { return "00:00" }
        var target = ISO8601DateFormatter().date(from: iso)
        if target == nil {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            target = f.date(from: iso)
        }
        guard let target else { return "00:00" }
        let s = max(0, Int(target.timeIntervalSince(now)))
        if s == 0 { return "It's time!" }
        let days = s / 86_400
        let hours = (s % 86_400) / 3600
        let mins = (s % 3600) / 60
        return days > 0
            ? "\(days)d \(String(format: "%02d:%02d", hours, mins))"
            : String(format: "%02d:%02d", hours, mins)
    }

    /// In-place editable version of the question card. Same paper-white
    /// pill, same "ask me anything" kicker and prompt — but the bottom
    /// row swaps the muted placeholder for a real TextField bound to
    /// the viewer's reply, with a send glyph that fires `onSubmitQuestion`.
    var authorUsername: String? = nil

    /// Floating avatar overlay placed above the top edge of the question
    /// card. Returns an `EmptyView` when no `authorUsername` was provided so
    /// the card layout is unchanged on callers that don't opt in.
    /// True when the card is rendering a baked-in answer (Q&A re-share).
    /// In that mode the original poster's avatar is intentionally hidden —
    /// the response card should show only the question + answer block.
    private var hasBakedAnswer: Bool {
        let trimmed = sticker.answer?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false)
    }

    @ViewBuilder
    private var questionAvatarOverlay: some View {
        if !hasBakedAnswer, let name = authorUsername, !name.isEmpty {
            WhisperAvatar(username: name, size: 32, ring: false)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .offset(y: -16)
        }
    }

    /// Extra top padding needed inside the card so the prompt text doesn't
    /// collide with the floating avatar. Zero when no avatar is shown.
    private var questionAvatarTopInset: CGFloat {
        (!hasBakedAnswer && authorUsername?.isEmpty == false) ? 12 : 0
    }

    @ViewBuilder
    private var editableQuestionCard: some View {
        let binding = editableQuestionText ?? .constant("")
        VStack(spacing: 10) {
            Text(sticker.text ?? "Ask me anything…")
                .font(.headline.weight(.bold))
                .foregroundStyle(cardForegroundColor)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Group {
                    if let focus = questionFieldFocused {
                        TextField(
                            "",
                            text: binding,
                            prompt: Text("Type something…").foregroundStyle(cardForegroundColor.opacity(0.45)),
                            axis: .vertical
                        )
                        .focused(focus)
                    } else {
                        TextField(
                            "",
                            text: binding,
                            prompt: Text("Type something…").foregroundStyle(cardForegroundColor.opacity(0.45)),
                            axis: .vertical
                        )
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(cardForegroundColor)
                .tint(cardForegroundColor)
                .multilineTextAlignment(.leading)
                .lineLimit(1...4)

            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(cardForegroundColor.opacity(isLightCard ? 0.05 : 0.18), in: .rect(cornerRadius: 12))
        }
        .padding(.top, 14 + questionAvatarTopInset)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: 240)
        .background(cardBackgroundColor, in: .rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .overlay(alignment: .top) { questionAvatarOverlay }
    }

    /// Wraps a sticker body in a Button when the viewer asked us to be
    /// interactive and provided an `onTap` callback. Otherwise renders the
    /// content as-is so the composer/preview stays draggable.
    @ViewBuilder
    private func tappableWrap<Content: View>(_ content: Content) -> some View {
        if isInteractive, let onTap {
            Button {
                let h = UIImpactFeedbackGenerator(style: .light); h.impactOccurred()
                onTap()
            } label: {
                content
                    // Force the Button's hit-test region to cover the
                    // entire visible sticker (including the soft shadow
                    // halo), so taps on the edges of the "ask me anything"
                    // card or @mention pill still register reliably.
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var textBubble: some View {
        let s = sticker.style ?? 0
        let fg = Color(hex: sticker.color ?? "#FFFFFF") ?? .white
        let bg = Color(hex: sticker.background ?? "#000000") ?? .black
        let font = WhisperStoryTypography.font(sticker.fontName, size: sticker.fontSize ?? (s == 5 ? 26 : s == 4 ? 30 : 28), style: s)
        return Text(sticker.text ?? "")
            .font(font)
            .multilineTextAlignment(WhisperStoryTypography.alignment(sticker.textAlignment))
            .frame(maxWidth: sticker.fontName != nil ? 350 : nil)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(fg)
            .padding(.horizontal, s == 0 ? 0 : 14)
            .padding(.vertical, s == 0 ? 0 : 8)
            .background {
                if s == 1 {
                    Capsule().fill(bg)
                } else if s == 2 {
                    Capsule().strokeBorder(bg, lineWidth: 2)
                } else if s == 4 {
                    RoundedRectangle(cornerRadius: 6).fill(bg)
                } else if s == 5 {
                    RoundedRectangle(cornerRadius: 4).fill(bg.opacity(0.88))
                }
            }
            .shadow(color: s == 0 ? .black.opacity(0.4) : .clear, radius: 4, x: 0, y: 1)
            .shadow(color: s == 3 ? fg.opacity(0.9) : .clear, radius: 6)
            .shadow(color: s == 3 ? fg.opacity(0.6) : .clear, radius: 14)
    }

    /// Card background color — author-picked palette stored on the
    /// sticker. Defaults to paper white.
    private var cardBackgroundColor: Color {
        (sticker.background.flatMap { Color(hex: $0) }) ?? .white
    }
    /// Foreground text color paired with the chosen card background.
    private var cardForegroundColor: Color {
        (sticker.color.flatMap { Color(hex: $0) }) ?? .black
    }
    /// Whether the picked card background is light enough to want a faint
    /// vs. a stronger contrast for the placeholder pill behind the prompt.
    private var isLightCard: Bool {
        // Treat the default white card as light. Cheap heuristic by hex.
        let hex = (sticker.background ?? "#FFFFFF").uppercased()
        return hex == "#FFFFFF" || hex == "#FFD93D"
    }

    private var questionCard: some View {
        let bakedAnswer = sticker.answer?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAnswer = (bakedAnswer?.isEmpty == false)
        return VStack(spacing: 10) {
            Group {
                if let authoring {
                    TextField("", text: authoring.text, prompt: Text("Ask me a question").foregroundStyle(cardForegroundColor.opacity(0.5)), axis: .vertical)
                        .focused(authoring.focus).tint(cardForegroundColor).lineLimit(1...4)
                        .accessibilityLabel("Question")
                } else { Text(sticker.text?.isEmpty == false ? sticker.text ?? "" : "Ask me a question") }
            }
                .font(.headline.weight(.bold))
                .foregroundStyle(cardForegroundColor)
                .multilineTextAlignment(.center)
            if hasAnswer, let answer = bakedAnswer {
                Text(answer)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.black, in: .rect(cornerRadius: 12))
            } else {
                Text("Type something…")
                    .font(.footnote)
                    .foregroundStyle(cardForegroundColor.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(cardForegroundColor.opacity(isLightCard ? 0.05 : 0.18), in: .rect(cornerRadius: 10))
            }
        }
        .padding(.top, 14 + questionAvatarTopInset)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: 240)
        .background(cardBackgroundColor, in: .rect(cornerRadius: 14))
        .overlay(alignment: .top) { questionAvatarOverlay }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    private var pollCard: some View {
        PollStickerBody(
            sticker: sticker,
            isInteractive: isInteractive,
            onVote: onVote,
            externalSelection: pendingPollSelection,
            onBeginInteract: onBeginInteract,
            tally: pollTally,
            votedIndex: votedIndex,
            authoring: authoring
        )
    }

    /// Shared kicker rendered on top of both the static + editable question
    /// cards. Pulled out so we can tune visibility in one place — heavier
    /// weight + a slightly darker grey reads cleanly on the paper-white card
    /// without competing with the bold prompt below it.
    private var questionKicker: some View {
        Text("ASK ME ANYTHING")
            .font(.caption2.weight(.heavy))
            .tracking(1.2)
            .foregroundStyle(cardForegroundColor.opacity(0.65))
    }

    private var sliderCard: some View {
        SliderStickerBody(
            sticker: sticker,
            isInteractive: isInteractive,
            onSlider: onSlider,
            externalValue: pendingSliderValue,
            onBeginInteract: onBeginInteract,
            authoring: authoring
        )
    }

    /// Compact paper label; viewer taps retain the existing Maps action.
    private var locationCard: some View {
        HStack(spacing: 7) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color(red: 0.48, green: 0.20, blue: 1))
            Text(sticker.label ?? "")
                .font(.subheadline.weight(.bold)).lineLimit(2)
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(.white, in: .rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private func pillCard(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white, in: .rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
    }

    private var musicChip: some View {
        HStack(spacing: 10) {
            if let art = sticker.musicArtwork, let url = URL(string: art) {
                WhisperCachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(.rect(cornerRadius: 6))
            } else {
                Image(systemName: "music.note")
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.2), in: .rect(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(sticker.musicTitle ?? "")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Text(sticker.musicArtist ?? "")
                    .font(.caption2)
                    .opacity(0.8)
                    .lineLimit(1)
            }
            Image(systemName: "music.note")
                .font(.caption.weight(.bold))
                .opacity(0.7)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white, in: .rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var gifThumb: some View {
        Group {
            if let urlStr = sticker.imageURL, let assetName = WhisperStoryTrayArtwork.bundledAsset(for: urlStr) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .accessibilityLabel(WhisperStoryTrayArtwork.allCases.first { $0.url == urlStr }?.title ?? "Story artwork")
            } else if let urlStr = sticker.imageURL, let jasperName = Self.jasperStickerName(from: urlStr) {
                Image("WhisperSticker_\(jasperName)")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    .background(Color.clear)
            } else if let urlStr = sticker.imageURL, let url = URL(string: urlStr) {
                WhisperAnimatedGIFView(url: url, contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .background(Color.clear)
            } else {
                Color.clear.frame(width: 120, height: 120)
            }
        }
        .background(Color.clear)
    }

    /// Parses our custom `jasper-sticker://<name>` URL scheme used to
    /// reference bundled Whisper sticker assets baked into the main app
    /// catalog (e.g. `WhisperSticker_ghost_crown`). Returns the bare name
    /// suffix (e.g. `ghost_crown`) or nil if the string isn't a Whisper
    /// sticker reference.
    static func jasperStickerName(from raw: String) -> String? {
        let prefix = "jasper-sticker://"
        guard raw.hasPrefix(prefix) else { return nil }
        let name = String(raw.dropFirst(prefix.count))
        return name.isEmpty ? nil : name
    }

    /// User-attached photo sticker — masked to the sticker's `shape`
    /// (rect · circle · heart · star · squircle). Tapping in the editor
    /// cycles the mask, exactly like Instagram's photo sticker.
    private var photoThumb: some View {
        let mask = WhisperStoryPhotoShape(rawValue: sticker.shape ?? "rect") ?? .rect
        let width: CGFloat
        if let fraction = sticker.cardWidthFraction, fraction.isFinite {
            width = CGFloat(min(1.0, max(0.1, fraction))) * stageWidth
        } else { width = 160 }
        let rawRatio: Double = sticker.mediaAspectRatio ?? 1.0
        let ratio: CGFloat = rawRatio.isFinite ? CGFloat(min(3.0, max(0.3, rawRatio))) : 1.0
        let height: CGFloat = mask == .rect ? width / ratio : width
        let framed = sticker.photoFrame == true
        return Group {
            if let urlStr = sticker.imageURL, let url = URL(string: urlStr) {
                WhisperCachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.clear
                    }
                }
                .frame(width: width, height: height)
                .clipped()
                .clipShape(mask.insettable)
                .padding(framed ? 8 : 0)
                .padding(.bottom, framed ? 24 : 0)
                .background(framed ? Color.white : .clear)
                .clipShape(.rect(cornerRadius: framed ? 3 : 0))
                .overlay {
                    mask.insettable
                        .stroke(.white.opacity(mask == .rect ? 0 : 0.9), lineWidth: 2.5)
                }
                .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            } else {
                Color.clear.frame(width: width, height: height)
                    .clipShape(mask.insettable)
            }
        }
        .background(Color.clear)
    }
}

// MARK: - Photo sticker shapes

/// The Instagram photo-sticker mask cycle. `next` steps rect → circle →
/// heart → star → squircle → rect. The web renders the same order with
/// CSS clip-paths, so a shape picked on one platform reads on the other.
nonisolated enum WhisperStoryPhotoShape: String, CaseIterable, Sendable {
    case rect, circle, heart, star, squircle

    var next: WhisperStoryPhotoShape {
        let all = Self.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }

    var label: String {
        switch self {
        case .rect: return "Original"
        case .circle: return "Circle"
        case .heart: return "Heart"
        case .star: return "Star"
        case .squircle: return "Rounded"
        }
    }

    /// A type-erased shape for `clipShape` + stroke overlays.
    @MainActor var insettable: AnyShape {
        switch self {
        case .rect: return AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        case .circle: return AnyShape(Circle())
        case .heart: return AnyShape(WhisperHeartShape())
        case .star: return AnyShape(WhisperStarShape(points: 5, innerRatio: 0.5))
        case .squircle: return AnyShape(RoundedRectangle(cornerRadius: 56, style: .continuous))
        }
    }
}

/// Classic two-lobe heart, drawn in the unit rect so it scales with the frame.
struct WhisperHeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h * 0.92))
        p.addCurve(
            to: CGPoint(x: rect.minX + w * 0.04, y: rect.minY + h * 0.36),
            control1: CGPoint(x: rect.minX + w * 0.22, y: rect.minY + h * 0.76),
            control2: CGPoint(x: rect.minX + w * 0.04, y: rect.minY + h * 0.58)
        )
        p.addCurve(
            to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h * 0.24),
            control1: CGPoint(x: rect.minX + w * 0.04, y: rect.minY + h * 0.06),
            control2: CGPoint(x: rect.minX + w * 0.36, y: rect.minY + h * 0.02)
        )
        p.addCurve(
            to: CGPoint(x: rect.minX + w * 0.96, y: rect.minY + h * 0.36),
            control1: CGPoint(x: rect.minX + w * 0.64, y: rect.minY + h * 0.02),
            control2: CGPoint(x: rect.minX + w * 0.96, y: rect.minY + h * 0.06)
        )
        p.addCurve(
            to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h * 0.92),
            control1: CGPoint(x: rect.minX + w * 0.96, y: rect.minY + h * 0.58),
            control2: CGPoint(x: rect.minX + w * 0.78, y: rect.minY + h * 0.76)
        )
        p.closeSubpath()
        return p
    }
}

/// Five-point star with rounded-feeling proportions.
struct WhisperStarShape: Shape {
    var points: Int = 5
    var innerRatio: CGFloat = 0.5

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        var p = Path()
        let total = max(points, 3) * 2
        for i in 0..<total {
            let r: CGFloat = i.isMultiple(of: 2) ? outer : inner
            let angle = (Double(i) * Double.pi / Double(max(points, 3))) - Double.pi / 2.0
            let pt = CGPoint(x: c.x + r * CGFloat(cos(angle)), y: c.y + r * CGFloat(sin(angle)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Muted, looping video preview inside the wave sticker (viewer only).
struct WhisperStoryWaveLoopView: View {
    let url: URL
    @State private var player: AVQueuePlayer = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?

    var body: some View {
        WhisperStoryWavePlayerLayer(player: player)
            .onAppear {
                guard looper == nil else { player.play(); return }
                let item = AVPlayerItem(url: url)
                looper = AVPlayerLooper(player: player, templateItem: item)
                player.isMuted = true
                player.play()
            }
            .onDisappear { player.pause() }
    }
}

private struct WhisperStoryWavePlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.backgroundColor = .clear
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
}

/// Slider sticker needs its own state for the draggable dot. On release
/// in interactive (viewer) mode we play an Instagram-style emoji burst:
/// a flock of the selected emoji floats up + fades, the thumb gets a
/// quick scale punch, and a "Sent!" pill confirms delivery.
private struct SliderStickerBody: View {
    let sticker: WhisperStorySticker
    let isInteractive: Bool
    let onSlider: ((Double) -> Void)?
    /// When bound, drag updates this binding instead of firing onSlider —
    /// commit is deferred to the parent's external Send pill.
    var externalValue: Binding<Double?>? = nil
    var onBeginInteract: (() -> Void)? = nil
    var authoring: WhisperStoryStickerAuthoring? = nil
    @State private var value: Double = 0.5
    @State private var burstID: Int = 0
    @State private var showSent: Bool = false
    @State private var thumbPunch: CGFloat = 1.0
    @State private var didBeginInteract: Bool = false

    /// Effective value to render. When the parent is driving us via
    /// `externalValue`, we mirror that. Otherwise we use our local state.
    private var renderValue: Double {
        if let ext = externalValue?.wrappedValue { return ext }
        return value
    }

    private var emoji: String { sticker.sliderEmoji ?? "❤️" }
    private var foreground: Color { sticker.color.flatMap { Color(hex: $0) } ?? .black }
    private var background: Color { sticker.background.flatMap { Color(hex: $0) } ?? .white }

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if let authoring {
                    TextField("Ask a question…", text: authoring.text, axis: .vertical)
                        .focused(authoring.focus).tint(foreground).lineLimit(1...4)
                } else { Text(sticker.text ?? "Slide to rate") }
            }
                .font(.headline.weight(.semibold))
                .foregroundStyle(foreground)
                .multilineTextAlignment(.center)
            GeometryReader { geo in
                let track = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(foreground.opacity(0.12))
                        .frame(height: 8)
                        .frame(maxWidth: .infinity)
                        .position(x: track / 2, y: 16)
                    // Emoji burst layer — a fresh batch is built on each
                    // burstID change so we get a clean animation cycle.
                    ForEach(0..<burstID * 6, id: \.self) { _ in
                        EmptyView()
                    }
                    if burstID > 0 {
                        SliderEmojiBurst(emoji: emoji, anchorX: max(16, min(track - 16, track * renderValue)))
                            .id(burstID)
                    }
                    Text(emoji)
                        .font(.system(size: 24 + CGFloat(renderValue) * 24))
                        .scaleEffect(thumbPunch)
                        .position(x: max(16, min(track - 16, track * renderValue)), y: 16)
                }
                .frame(height: 48)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard isInteractive else { return }
                            let v = max(0, min(1, g.location.x / track))
                            if !didBeginInteract {
                                didBeginInteract = true
                                onBeginInteract?()
                            }
                            if let ext = externalValue {
                                ext.wrappedValue = v
                            } else {
                                value = v
                            }
                        }
                        .onEnded { _ in
                            guard isInteractive else { return }
                            // Parent-driven mode: don't auto-commit, don't
                            // flash the internal "Sent!" toast — the
                            // lifted overlay's external Send pill handles it.
                            if externalValue != nil { return }
                            onSlider?(value)
                            // Punch the thumb, fire the emoji burst, and
                            // briefly show the "Sent!" confirmation pill.
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
                                thumbPunch = 1.55
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.18)) {
                                thumbPunch = 1.0
                            }
                            burstID += 1
                            withAnimation(.easeOut(duration: 0.22)) { showSent = true }
                            Task {
                                try? await Task.sleep(for: .milliseconds(1100))
                                await MainActor.run {
                                    withAnimation(.easeIn(duration: 0.25)) { showSent = false }
                                }
                            }
                        }
                )
            }
            .frame(height: 48)
        }
        .padding(14)
        .frame(width: 240)
        .background(background, in: .rect(cornerRadius: 18))
        .overlay(alignment: .top) {
            if showSent {
                Text("Sent!")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.85), in: Capsule())
                    .offset(y: -28)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

/// One-shot upward emoji burst played when the viewer releases the slider.
/// Spawns six emoji that float up + fade + scale; the parent re-creates the
/// view via `.id(burstID)` to replay the animation on every release.
private struct SliderEmojiBurst: View {
    let emoji: String
    let anchorX: CGFloat
    @State private var animated: Bool = false

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                let dx: CGFloat = CGFloat(i - 3) * 14 + CGFloat.random(in: -6...6)
                let delay: Double = Double(i) * 0.05
                let rise: CGFloat = -CGFloat.random(in: 70...110)
                Text(emoji)
                    .font(.system(size: CGFloat.random(in: 18...30)))
                    .offset(x: animated ? dx : 0, y: animated ? rise : 0)
                    .scaleEffect(animated ? CGFloat.random(in: 0.7...1.3) : 0.4)
                    .opacity(animated ? 0 : 1)
                    .animation(.easeOut(duration: 0.9).delay(delay), value: animated)
            }
        }
        .position(x: anchorX, y: 16)
        .allowsHitTesting(false)
        .onAppear { animated = true }
    }
}

/// Poll body with vote-confirmation animation — selected option scales
/// + highlights, a check pops in, and a "Sent!" pill confirms delivery.
private struct PollStickerBody: View {
    let sticker: WhisperStorySticker
    let isInteractive: Bool
    let onVote: ((Int) -> Void)?
    /// When bound, tapping an option just sets this — commit is deferred
    /// to the parent's external Send pill (matches the lifted/blurred
    /// pattern the question card uses).
    var externalSelection: Binding<Int?>? = nil
    var onBeginInteract: (() -> Void)? = nil
    /// Vote counts per option. When set, the card switches to results mode.
    var tally: [Int]? = nil
    /// Index the viewer voted for — highlighted in results mode.
    var votedIndex: Int? = nil
    var authoring: WhisperStoryStickerAuthoring? = nil
    @State private var selected: Int? = nil
    @State private var showSent: Bool = false

    /// Effective selected index — parent's binding wins when present.
    private var effectiveSelected: Int? {
        externalSelection?.wrappedValue ?? selected
    }

    var body: some View {
        let options = sticker.pollOptions ?? ["Yes", "No"]
        return VStack(spacing: 10) {
            if let authoring {
                TextField("ASK A QUESTION…", text: authoring.text, axis: .vertical)
                    .focused(authoring.focus).tint(Color(hex: sticker.color ?? "#111111") ?? .black)
                    .font(.headline.weight(.bold)).multilineTextAlignment(.center).lineLimit(1...4)
                    .accessibilityLabel("Poll question")
            } else if let q = sticker.text, !q.isEmpty {
                Text(q)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(hex: sticker.color ?? "#111111") ?? .black)
                    .multilineTextAlignment(.center)
            }
            if let authoring, let optionBinding = authoring.options {
                VStack(spacing: 6) {
                    ForEach(Array(optionBinding.wrappedValue.enumerated()), id: \.offset) { index, _ in
                        TextField("Choice \(index + 1)", text: Binding(get: {
                            optionBinding.wrappedValue.indices.contains(index) ? optionBinding.wrappedValue[index] : ""
                        }, set: { value in
                            guard optionBinding.wrappedValue.indices.contains(index) else { return }
                            var values = optionBinding.wrappedValue
                            values[index] = String(value.prefix(max(80, values[index].count)))
                            optionBinding.wrappedValue = values
                        }))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.black).tint(.black)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(.black.opacity(0.06), in: .rect(cornerRadius: 8))
                        .environment(\.colorScheme, .light)
                        .accessibilityLabel("Poll choice \(index + 1)")
                    }
                    if optionBinding.wrappedValue.count < 4 {
                        Button("Add another option") { optionBinding.wrappedValue.append("") }
                            .font(.caption).foregroundStyle(.gray).frame(minHeight: 44)
                    }
                }
            } else if let counts = tally {
                pollResults(options: options, counts: counts)
            } else {
                pollOptionsRow(options: options)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .frame(width: 240)
        .background(Color(hex: sticker.background ?? "#FFFFFF") ?? .white, in: .rect(cornerRadius: 12))
        .overlay(alignment: .top) {
            if showSent {
                Text("Sent!")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.85), in: Capsule())
                    .offset(y: -28)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func pollResults(options: [String], counts: [Int]) -> some View {
        let total = max(1, counts.reduce(0, +))
        VStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                let n = idx < counts.count ? counts[idx] : 0
                let pct = Int(round(Double(n) / Double(total) * 100))
                let mine = (votedIndex == idx)
                let frac = CGFloat(n) / CGFloat(total)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.06))
                        RoundedRectangle(cornerRadius: 10)
                            .fill(mine ? Color.green.opacity(0.34) : Color.black.opacity(0.16))
                            .frame(width: max(10, geo.size.width * frac))
                            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: frac)
                        HStack(spacing: 6) {
                            Text(opt)
                                .font(.subheadline.weight(mine ? .heavy : .semibold))
                                .foregroundStyle(.black)
                            if mine {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.green)
                            }
                            Spacer(minLength: 4)
                            Text("\(pct)%")
                                .font(.subheadline.weight(.heavy).monospacedDigit())
                                .foregroundStyle(.black)
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .frame(height: 34)
            }
        }
    }

    @ViewBuilder
    private func pollOptionsRow(options: [String]) -> some View {
        VStack(spacing: 6) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    Button {
                        guard isInteractive else { return }
                        let h = UIImpactFeedbackGenerator(style: .medium); h.impactOccurred()
                        if let ext = externalSelection {
                            // Parent-driven: just update binding, never
                            // auto-commit. Allow changing the pick.
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
                                ext.wrappedValue = idx
                            }
                            onBeginInteract?()
                            return
                        }
                        guard selected == nil else { return }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
                            selected = idx
                        }
                        onVote?(idx)
                        withAnimation(.easeOut(duration: 0.22).delay(0.1)) { showSent = true }
                        Task {
                            try? await Task.sleep(for: .milliseconds(1200))
                            await MainActor.run {
                                withAnimation(.easeIn(duration: 0.25)) { showSent = false }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(opt)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.black)
                            if effectiveSelected == idx {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(.black.opacity(0.06), in: .rect(cornerRadius: 8))
                        .background {
                            if effectiveSelected == idx {
                                Color.green.opacity(0.18)
                                    .transition(.opacity)
                            }
                        }
                        .scaleEffect(effectiveSelected == idx ? 1.08 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
        }
    }
}

// MARK: - Color helpers

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
