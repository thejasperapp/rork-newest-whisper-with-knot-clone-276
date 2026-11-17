import SwiftUI

/// Whisper uses a strict monochrome palette à la Instagram. Surfaces are
/// warm white in light mode and true OLED black in dark mode; ink (text/icons)
/// inverts. There is no chromatic accent — emphasis comes from weight,
/// contrast, and motion. Blue lives ONLY in small accents (story rings,
/// verified badges) where it pops against the neutral stage.
enum WhisperTheme {
    /// Legacy names retained for callers; all dark canvases are true black.
    static let darkIndigo = Color.black
    static let darkIndigoCard = Color(white: 0.09)
    /// Raised card tone for Pitch Black mode — just above true black so
    /// cards still read as distinct surfaces on OLED.
    static let pitchBlackCard = Color(white: 0.09)

    /// The single chromatic exception in Whisper's monochrome system — the
    /// like heart. Every surface (feed card, grid card, detail view,
    /// comment rows) must use this exact red so hearts never drift between
    /// screens.
    static let likeRed = Color(red: 0.92, green: 0.25, blue: 0.35)

    static func surface(_ scheme: ColorScheme) -> Color {
        guard scheme == .dark else { return WhisperChatPalette.rgb(0xFAF9F6) }
        return .black
    }

    /// Slightly raised card surface — near-white on light, raised indigo
    /// (or near-black in Pitch Black mode) on dark.
    static func card(_ scheme: ColorScheme) -> Color {
        guard scheme == .dark else { return WhisperChatPalette.rgb(0xEFEEEA) }
        return pitchBlackCard
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? WhisperChatPalette.rgb(0xF3F3EE) : WhisperChatPalette.rgb(0x202729)
    }

    /// "Accent" is just ink — kept as a name so call sites don't have to know.
    static func accent(_ scheme: ColorScheme) -> Color { ink(scheme) }

    /// Hairline divider tone that reads on both surfaces.
    static func hairline(_ scheme: ColorScheme) -> Color {
        guard scheme == .dark else { return Color.black.opacity(0.08) }
        return Color.white.opacity(0.16)
    }

    /// Muted secondary tone for timestamps, captions, helper text.
    static func muted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? WhisperChatPalette.rgb(0xA7B0B0) : WhisperChatPalette.rgb(0x647071)
    }
}

// MARK: - Stories underlayer

/// A continuous content surface over the recessed canvas, matching profile details.
/// Apply to the container, not individual rows; leave content unclipped for overlays.
struct WhisperStoriesForeground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                    .fill(WhisperTheme.surface(scheme))
            }
    }
}

// MARK: - Motion

/// Whisper's shared motion language — every screen should reach for one of
/// these three springs instead of ad-hoc values so taps, list changes, and
/// reveals all feel like the same product.
extension Animation {
    /// Quick UI feedback — button presses, chip toggles, badge pops.
    static let whisperSnappy = Animation.spring(response: 0.3, dampingFraction: 0.8)
    /// Content changes — feed re-ranks, list insertions, section reveals.
    static let whisperSmooth = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Large surfaces — overlays, full-screen state changes.
    static let whisperGentle = Animation.spring(response: 0.5, dampingFraction: 0.88)
}

// MARK: - Sheet border

/// Hairline stroke around a popup sheet's rounded top edge so the sheet
/// reads as a distinct surface in dark mode (where both the sheet body
/// and the system backdrop are near-black). No effect in light mode.
struct WhisperSheetBorderModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if colorScheme == .dark {
                UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cornerRadius,
                    style: .continuous
                )
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Adds a subtle hairline stroke around the top edge of a popup sheet
    /// for dark mode separation. Call AFTER `presentationCornerRadius` so
    /// the stroke matches. Pass the same radius the sheet uses (default 22).
    func whisperSheetBorder(cornerRadius: CGFloat = 22) -> some View {
        modifier(WhisperSheetBorderModifier(cornerRadius: cornerRadius))
    }
}

/// Whisper's "W" wordmark — the looped script logo. Rendered as a template
/// image so the same asset adapts to both light and dark mode automatically.
struct WhisperWordmark: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 30
    var refreshStatus: WhisperRefreshStatus = .init()

    var body: some View {
        WhisperTraceLogo(
            size: size * 1.6,
            manualProgress: refreshStatus.isPulling
                ? (refreshStatus.isRefreshing ? nil : (refreshStatus.pullProgress > 0.008 ? refreshStatus.pullProgress : 1))
                : 1
        )
        .frame(height: size * 1.8)
        .accessibilityHidden(false)
        .accessibilityLabel("Whisper")
        .accessibilityValue(refreshStatus.isRefreshing ? "Refreshing" : "")
    }
}

/// Solid warm-orange backdrop used behind every Whisper avatar — matches
/// the Whisper brand reference exactly. Intentionally NOT a gradient so the
/// avatar reads as a single flat colour disc, like the brand mascot card.
enum WhisperAvatarPalette {
    /// Flat warm orange — same swatch on every avatar.
    static let backdrop = Color(red: 0.98, green: 0.58, blue: 0.32)
}

/// Circular avatar with the Whisper warm peach/orange backdrop. Used
/// everywhere a user shows up. The orange gradient is always present —
/// when a photo is set it sits *on top* of the gradient (so transparent
/// PNGs and partially-loaded images always feel branded), and when there's
/// no image at all the gradient + initial form the placeholder.
///
/// When the username matches the currently signed-in user, this view
/// automatically pulls `profileImageURL` from `AuthenticationService` so
/// Whisper and Whisper share the same avatar without per-call wiring.
struct WhisperAvatar: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var auth = AuthenticationService.shared
    let username: String
    var size: CGFloat = 38
    var imageData: Data? = nil
    var imageURL: URL? = nil
    var ring: Bool = false

    /// Resolves to the user's avatar URL when this avatar represents the
    /// current user — otherwise honours an explicit `imageURL` if provided.
    private var resolvedURL: URL? {
        if let imageURL { return imageURL }
        let me = (LeaderboardService.shared.savedUsername ?? auth.currentUser.username ?? "").lowercased()
        let target = username.lowercased()
        if !me.isEmpty, me == target || target == "you",
           let s = auth.currentUser.profileImageURL,
           let u = URL(string: s) {
            return u
        }
        // Fall back to the cached author-profile lookup so other users in
        // the feed render their real profile picture (instead of just the
        // initial-on-orange placeholder).
        if !target.isEmpty,
           let s = WhisperBackendService.shared.avatarURLString(forUsername: target),
           let u = URL(string: s) {
            return u
        }
        return nil
    }

    /// True when this avatar represents the Jasper AI assistant. We render
    /// THE Jasper icon (the peach squircle with the dark ghost) so `@ember` /
    /// `@jasper` surfaces show the one Jasper mark instead of an initial.
    private var isEmber: Bool {
        let lower = username.lowercased()
        return lower == "knot" || lower == "ember" || lower == "jasper"
    }

    var body: some View {
        let initial = username.first.map { String($0).uppercased() } ?? "?"
        ZStack {
            // Solid warm-orange backdrop — single flat brand colour, no
            // gradient. Visible as the fallback when no photo is set, and
            // peeking through transparent PNGs.
            Circle()
                .fill(WhisperAvatarPalette.backdrop)
                .frame(width: size, height: size)

            if isEmber {
                // Keep the established assistant identities; only their artwork changes.
                Circle()
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: size, height: size)
                    .overlay {
                        WhisperKnotMascot(size: size * 0.94)
                    }
                    .clipShape(Circle())
            } else if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let url = resolvedURL {
                WhisperCachedAsyncImage(url: url, maxPixelSize: Int(ceil(size * 3 / 64)) * 64) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Text(initial)
                            .font(.system(size: size * 0.42, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .overlay {
            if ring {
                Circle()
                    .strokeBorder(WhisperTheme.ink(colorScheme), lineWidth: 2)
                    .padding(-3)
            }
        }
        .task(id: username) {
            // Self-heal: if no photo URL is cached for this handle yet, run a
            // one-shot profile lookup so avatars hydrate even on surfaces that
            // mount before the batch author hydration ran (deduped per session
            // inside the service).
            guard imageData == nil, imageURL == nil, !isEmber, resolvedURL == nil else { return }
            await WhisperBackendService.shared.hydrateAvatar(forUsername: username)
        }
    }
}

/// Avatar wrapped with the IG-Notes-style chrome shown on the Whisper
/// profile and story strip: optional black story ring, optional black `+`
/// button at the bottom-right, and an optional thought bubble overlapping
/// the top-left of the avatar — exactly like the brand reference.
///
/// Hit-testing: when `onPlusTap` / `onBubbleTap` are provided, those areas
/// become independent buttons. The bare avatar disc is *not* a button — so
/// callers don't have to (and shouldn't) wrap the chrome in their own
/// Button when they want split tap zones.
struct WhisperAvatarChrome<TrailingOverlay: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let username: String
    /// Diameter of the avatar disc itself (the chrome adds extra space).
    var size: CGFloat = 84
    var imageData: Data? = nil
    var imageURL: URL? = nil
    /// Whether to draw the unread-story ring around the avatar.
    var storyRing: Bool = true
    /// Override colour for the story ring. Defaults to the active ink colour.
    /// Used to highlight "your story" with a brand blue ring.
    var ringTint: Color? = nil
    /// Draw the Instagram conic-gradient story ring (unseen stories)
    /// instead of a solid tint — the iconic yellow→orange→magenta→purple.
    var gradientRing: Bool = false
    /// Show the black `+` (or pencil) at bottom-right.
    var plusButton: Bool = false
    /// SF Symbol for the corner button (default `plus`, switches to
    /// `pencil` when the user already has an active thought).
    var plusSymbol: String = "plus"
    /// Optional compact portrait badge; default chrome remains unchanged.
    var plusDiameter: CGFloat? = nil
    /// Optional thought text shown in the IG-Notes bubble overlapping the
    /// top-left of the avatar.
    var thoughtText: String? = nil
    /// Visual treatment for the thought bubble (plain / location / music).
    var thoughtStyle: WhisperThoughtStyle = .plain
    /// Secondary line for styled bubbles (e.g. city or song title).
    var thoughtAccent: String = ""
    /// Emoji corner badge on the bubble.
    var thoughtEmoji: String = ""
    /// Optional hex override for the bubble background.
    var thoughtColorHex: String = ""
    /// Visual scale for the bubble — 1.0 ≈ profile size, ~0.55 ≈ story strip.
    var bubbleScale: CGFloat = 1.0
    /// When true, the thought bubble gently breathes (subtle scale +
    /// opacity loop) to signal unread replies without altering its layout.
    var bubblePulse: Bool = false
    /// Profiles overlay notes over the cover instead of reserving portrait space.
    var reservesThoughtSpace: Bool = true
    /// Action for tapping the `+` corner button (e.g. post a story).
    var onPlusTap: (() -> Void)? = nil
    /// Action for tapping the thought bubble (e.g. open the composer).
    var onBubbleTap: (() -> Void)? = nil
    /// Optional trailing overlay (e.g. a verified badge).
    @ViewBuilder var trailing: () -> TrailingOverlay

    init(
        username: String,
        size: CGFloat = 84,
        imageData: Data? = nil,
        imageURL: URL? = nil,
        storyRing: Bool = true,
        ringTint: Color? = nil,
        gradientRing: Bool = false,
        plusButton: Bool = false,
        plusSymbol: String = "plus",
        plusDiameter: CGFloat? = nil,
        thoughtText: String? = nil,
        thoughtStyle: WhisperThoughtStyle = .plain,
        thoughtAccent: String = "",
        thoughtEmoji: String = "",
        thoughtColorHex: String = "",
        bubbleScale: CGFloat = 1.0,
        bubblePulse: Bool = false,
        reservesThoughtSpace: Bool = true,
        onPlusTap: (() -> Void)? = nil,
        onBubbleTap: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> TrailingOverlay = { EmptyView() }
    ) {
        self.username = username
        self.size = size
        self.imageData = imageData
        self.imageURL = imageURL
        self.storyRing = storyRing
        self.ringTint = ringTint
        self.gradientRing = gradientRing
        self.plusButton = plusButton
        self.plusSymbol = plusSymbol
        self.plusDiameter = plusDiameter
        self.thoughtText = thoughtText
        self.thoughtStyle = thoughtStyle
        self.thoughtAccent = thoughtAccent
        self.thoughtEmoji = thoughtEmoji
        self.thoughtColorHex = thoughtColorHex
        self.bubbleScale = bubbleScale
        self.bubblePulse = bubblePulse
        self.reservesThoughtSpace = reservesThoughtSpace
        self.onPlusTap = onPlusTap
        self.onBubbleTap = onBubbleTap
        self.trailing = trailing
    }

    private var ringPad: CGFloat { storyRing ? 4 : 0 }
    private var plusSize: CGFloat { plusDiameter ?? max(20, size * 0.30) }
    /// Drives the gentle breathe animation when `bubblePulse` is on.
    @State private var pulseOn: Bool = false

    var body: some View {
        ZStack {
            // Story ring (thin, ink-coloured) sized just outside the avatar.
            // Only drawn when the user has an active/fresh story.
            if storyRing {
                // Instagram parity: the conic gradient ring for unseen
                // stories, a solid tint when provided, and a neutral gray
                // hairline when seen — users still know the avatar has a
                // story even after viewing.
                if gradientRing {
                    Circle()
                        .strokeBorder(WhisperIGRing.gradient, lineWidth: 3)
                        .frame(width: size + ringPad * 2, height: size + ringPad * 2)
                } else {
                    Circle()
                        .strokeBorder(
                            ringTint ?? WhisperTheme.muted(colorScheme).opacity(0.55),
                            lineWidth: ringTint == nil ? 1.5 : 2.5
                        )
                        .frame(width: size + ringPad * 2, height: size + ringPad * 2)
                }
            }
            WhisperAvatar(
                username: username,
                size: size,
                imageData: imageData,
                imageURL: imageURL,
                ring: false
            )
        }
        .frame(width: size + ringPad * 2, height: size + ringPad * 2)
        // Bottom-right black `+` button overlapping the avatar edge.
        .overlay(alignment: .bottomTrailing) {
            if plusButton {
                Button {
                    Haptics.tap()
                    onPlusTap?()
                } label: {
                    Image(systemName: plusSymbol)
                        .font(.system(size: plusSize * 0.5, weight: .heavy))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(width: plusSize, height: plusSize)
                        .background(
                            Circle().fill(WhisperTheme.ink(colorScheme))
                        )
                        .overlay(
                            Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 2)
                        )
                        .frame(width: plusDiameter == nil ? plusSize : 44, height: plusDiameter == nil ? plusSize : 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(onPlusTap == nil)
                .accessibilityLabel("Add to story")
                .offset(x: plusDiameter == nil ? plusSize * 0.10 : 0, y: plusDiameter == nil ? plusSize * 0.10 : 0)
            }
        }
        // IG-Notes bubble centered above the avatar with its tail dipping
        // into the top ~10% of the profile photo — matches the Instagram
        // "Notes" reference exactly.
        //
        // We only wrap the bubble in a `Button` when the caller supplies
        // an `onBubbleTap` handler. Previously we always wrapped + applied
        // `.disabled(onBubbleTap == nil)`, which made other users' bubbles
        // render with the system disabled treatment (≈40% opacity) and
        // look dim/ghosted in the stories strip.
        .overlay(alignment: .top) {
            if let t = thoughtText, !t.isEmpty {
                Group {
                    if let action = onBubbleTap {
                        Button {
                            Haptics.tap()
                            action()
                        } label: {
                            WhisperThoughtBubble(
                                text: t,
                                scale: bubbleScale,
                                style: thoughtStyle,
                                accent: thoughtAccent,
                                emoji: thoughtEmoji,
                                colorHex: thoughtColorHex
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Non-interactive bubble — render at full opacity
                        // and let taps pass through to the parent (e.g. the
                        // story-open Button wrapping the whole avatar).
                        WhisperThoughtBubble(
                            text: t,
                            scale: bubbleScale,
                            style: thoughtStyle,
                            accent: thoughtAccent,
                            emoji: thoughtEmoji,
                            colorHex: thoughtColorHex
                        )
                        .allowsHitTesting(false)
                    }
                }
                // Gentle breathe to signal unread replies — purely visual,
                // doesn't change the bubble's layout footprint so neighbors
                // in a horizontal strip stay put.
                .scaleEffect(bubblePulse ? (pulseOn ? 1.04 : 1.0) : 1.0)
                .animation(
                    bubblePulse
                        ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                        : .default,
                    value: pulseOn
                )
                .onAppear { if bubblePulse { pulseOn = true } }
                .onChange(of: bubblePulse) { _, newValue in pulseOn = newValue }
                // Pull the bubble down so the *box* itself overlaps the
                // top ~10% of the avatar — the tail dots dip further in,
                // matching the Instagram Notes reference exactly. Uses the
                // bubble's measured height so the compact single-line pill
                // anchors its bottom at the same overlap point as the full
                // 2-line note.
                .offset(y: -(WhisperThoughtBubble.measuredHeight(
                    text: t,
                    style: thoughtStyle,
                    scale: bubbleScale
                ) - 12 * bubbleScale - size * 0.10))
                // Block the bubble (plus emoji badge offset) from spilling
                // into the neighboring strip column. Without this, a
                // friend's bubble could visually sit on top of the
                // adjacent "Your story" / "What's on your mind?" bubble
                // because the bubble is wider than the avatar.
                .frame(width: size + ringPad * 2)
            }
        }
        // Reserve top space so the bubble doesn't get clipped by parents.
        .padding(.top, reservedThoughtHeight)
        .overlay(alignment: .topTrailing) { trailing() }
    }

    private var reservedThoughtHeight: CGFloat {
        guard reservesThoughtSpace, let text = thoughtText, !text.isEmpty else { return 0 }
        // Reserve the actual overflow, not a fixed 38-point shelf even for
        // a tiny Note prompt. Tall music/two-line notes keep their clearance.
        return max(0, WhisperThoughtBubble.measuredHeight(text: text, style: thoughtStyle, scale: bubbleScale)
                   - 12 * bubbleScale - size * 0.10) + (thoughtEmoji.isEmpty ? 4 : 16 * bubbleScale)
    }
}
