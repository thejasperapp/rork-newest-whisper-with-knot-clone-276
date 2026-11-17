import SwiftUI

/// Shared reference-matched chat geometry: soft, uniformly rounded bubbles.
/// The default palette is pale blue/gray; explicitly selected themes remain intact.
enum WhisperChatStyle {
    /// Body text inside bubbles.
    static let bodyFont: Font = .callout
    /// Horizontal / vertical padding inside a text bubble.
    static let bubbleHorizontal: CGFloat = 14
    static let bubbleVertical: CGFloat = 9
    /// Shared radius for soft, continuous bubble corners.
    static let bigRadius: CGFloat = 22

    /// Your bubble fill — the theme's ink at 90%, so the bubble breathes a
    /// little against the surface instead of sitting as a flat black slab.
    static func ownFill(_ scheme: ColorScheme) -> Color { WhisperTheme.ink(scheme).opacity(ownFillOpacity) }
    /// The ink opacity of your bubbles.
    static let ownFillOpacity: Double = 0.9
    /// A QUOTED copy of your bubble (inside a reply) — lighter ink.
    static func ownQuoteFill(_ scheme: ColorScheme) -> Color { WhisperTheme.ink(scheme).opacity(0.42) }
    /// A QUOTED copy of their bubble (inside a reply).
    static func theirQuoteFill(_ scheme: ColorScheme) -> Color { WhisperTheme.card(scheme).opacity(0.7) }
    /// Text on your bubble — the theme's surface.
    static func ownText(_ scheme: ColorScheme) -> Color { WhisperTheme.surface(scheme) }
    /// Everyone else's bubble fill.
    static func theirFill(_ scheme: ColorScheme) -> Color { WhisperTheme.card(scheme) }
    /// Text on their bubble.
    static func theirText(_ scheme: ColorScheme) -> Color { WhisperTheme.ink(scheme) }

    /// Keep the same soft silhouette for individual bubbles and grouped runs.
    static func shape(mine: Bool, isFirstInRun: Bool, isLastInRun: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: bigRadius, bottomLeading: bigRadius, bottomTrailing: bigRadius, topTrailing: bigRadius), style: .continuous)
    }

    /// The calm arrival: a message settles in from its own corner with a
    /// touch of scale and a fade. `mine` anchors bottom-trailing (it grows
    /// out of the composer), theirs bottom-leading.
    static func arrive(mine: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.94, anchor: mine ? .bottomTrailing : .bottomLeading)
                .combined(with: .opacity),
            removal: .opacity
        )
    }

    /// The spring every chat surface uses for arrivals and composer swaps.
    static let spring: Animation = .spring(duration: 0.28, bounce: 0)
}

/// A plain text bubble using the conversation's selected palette.
struct WhisperChatTextBubble: View {
    let text: String
    let mine: Bool
    var isFirstInRun: Bool = true
    var isLastInRun: Bool = true
    var knotContrast = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.whisperChatAppearance) private var appearance
    @Environment(\.whisperChatDesign) private var design

    var body: some View {
        Text(text)
            .font(WhisperChatStyle.bodyFont)
            .foregroundStyle(knotContrast && colorScheme == .dark ? .white : (design?.palette(colorScheme) ?? appearance.palette(colorScheme)).text(mine: mine))
            .padding(.horizontal, WhisperChatStyle.bubbleHorizontal)
            .padding(.vertical, WhisperChatStyle.bubbleVertical)
            .background {
                WhisperChatStyle.shape(mine: mine, isFirstInRun: isFirstInRun, isLastInRun: isLastInRun)
                    .fill((design?.palette(colorScheme) ?? appearance.palette(colorScheme)).fill(mine: mine))
                    .modifier(WhisperChatScrollTint(mine: mine))
                    .overlay {
                        if knotContrast && mine && colorScheme == .dark {
                            WhisperChatStyle.shape(mine: mine, isFirstInRun: isFirstInRun, isLastInRun: isLastInRun)
                                .fill(Color(red: 0.08, green: 0.20, blue: 0.38))
                        }
                    }
            }
    }
}

/// A bare ink glyph in a 36pt hit area — the composer's quick tools.
struct WhisperChatToolButton: View {
    let systemImage: String
    var label: String? = nil
    var accessibility: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.whisperChatAppearance) private var appearance
    @Environment(\.whisperChatDesign) private var design
    private var palette: WhisperChatPalette { design?.palette(colorScheme) ?? appearance.palette(colorScheme) }

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Group {
                if let label {
                    Text(label)
                        .font(.system(size: 11, weight: .heavy))
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 19, weight: .regular))
                }
            }
            .foregroundStyle(palette.incomingText.opacity(0.86))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}

/// The composer action — the same palette-colored disc for send and stop;
/// muted while there's nothing to send.
struct WhisperChatSendButton: View {
    let enabled: Bool
    let sending: Bool
    var stopping = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.whisperChatAppearance) private var appearance
    @Environment(\.whisperChatDesign) private var design
    private var palette: WhisperChatPalette { design?.palette(colorScheme) ?? appearance.palette(colorScheme) }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(enabled ? palette.outgoing : palette.incomingText.opacity(0.25))
                    .frame(width: 34, height: 34)
                if sending {
                    ProgressView()
                        .tint(palette.outgoingText)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: stopping ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.outgoingText)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || sending)
        .animation(WhisperChatStyle.spring, value: enabled)
        .accessibilityLabel(stopping ? "Stop response" : "Send")
    }
}

/// The composer's leading "+" — a bare ink glyph (no disc) that turns into
/// an × while the attach tray is up.
struct WhisperChatPlusButton: View {
    let isOpen: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.whisperChatAppearance) private var appearance
    @Environment(\.whisperChatDesign) private var design
    private var palette: WhisperChatPalette { design?.palette(colorScheme) ?? appearance.palette(colorScheme) }

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(palette.incomingText)
                .rotationEffect(.degrees(isOpen ? 45 : 0))
                .frame(width: 44, height: 44)
                .modifier(WhisperControlGlass(shape: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9), value: isOpen)
        .accessibilityLabel(isOpen ? "Close attachments" : "Attach")
    }
}

/// The field that holds the draft — a rounded card with a hairline that
/// tints to ink when focused. Content is the TextField (+ anything trailing
/// the caller wants inside).
struct WhisperChatField<Content: View>: View {
    let focused: Bool
    var transparent = false
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.whisperChatAppearance) private var appearance
    @Environment(\.whisperChatDesign) private var design
    private var palette: WhisperChatPalette { design?.palette(colorScheme) ?? appearance.palette(colorScheme) }

    var body: some View {
        Group {
            if transparent {
                content()
                    .background(.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(palette.incomingText.opacity(focused ? 0.3 : 0.16), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
            } else {
                content().modifier(WhisperControlGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

// MARK: - Reply quotes

/// Reply grammar shared by 1:1 threads and groups — the quote rides the
/// body in plain text (`↩ @name: "quote…"\n\nreply`) so every client reads
/// it, and the renderer lifts it back out into the quoted-bubble look.
/// What a quoted message IS — so a reply can show a MINI version of a card
/// or photo instead of the card itself (or its raw wire).
struct WhisperChatQuotePreview {
    /// The friendly line ("Shared a wave · caption…", "Photo", or the text).
    let label: String
    /// SF symbol for card/media quotes; nil for plain text.
    let icon: String?
    /// A small image for the mini card when the original has one.
    let thumbnailURL: URL?

    var isCard: Bool { icon != nil || thumbnailURL != nil }
}

enum WhisperChatReply {
    /// The quote (if any) and the reply text of a body.
    nonisolated static func split(_ body: String) -> (quote: WhisperGroupReplyQuote?, text: String) {
        WhisperGroupChatService.splitReply(body)
    }

    /// Builds the wire body for a reply to `quoted`.
    static func body(quoting quoted: WhisperMessageRow, with text: String) -> String {
        WhisperGroupChatService.replyBody(quoting: quoted, with: text)
    }

    /// Describes a body for quoting: media and every card collapse to a
    /// friendly label (+ icon, + thumbnail when there is one); plain text
    /// stays plain text. The label is DETERMINISTIC, so the sender writes it
    /// into the quote and the receiver can find the original by it.
    static func preview(for body: String) -> WhisperChatQuotePreview {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // A reply quoting a reply — quote the reply's own text.
        if trimmed.hasPrefix("↩ @") {
            let inner = split(trimmed)
            if inner.quote != nil { return preview(for: inner.text) }
        }
        if WhisperDMThreadView.videoURL(in: trimmed) != nil {
            return WhisperChatQuotePreview(label: "Video", icon: "play.rectangle", thumbnailURL: nil)
        }
        if let url = WhisperDMThreadView.imageURL(in: trimmed) {
            let lower = url.absoluteString.lowercased()
            let isGIF = lower.contains(".gif") || (url.host?.lowercased().contains("giphy.com") ?? false)
            return WhisperChatQuotePreview(label: isGIF ? "GIF" : "Photo", icon: isGIF ? "rectangle.stack" : "photo", thumbnailURL: url)
        }
        if WhisperStickerPack.isWhisperSticker(trimmed) {
            return WhisperChatQuotePreview(label: "Sticker", icon: "face.smiling", thumbnailURL: nil)
        }
        if trimmed.hasPrefix(WhisperSharedCommunityEmbed.prefix) {
            let community = WhisperSharedCommunityEmbed.decode(trimmed).flatMap { WhisperSharedCommunityEmbed.community(for: $0) }
            return WhisperChatQuotePreview(label: community.map { "Shared \($0.name)" } ?? "Shared a community", icon: "person.2", thumbnailURL: nil)
        }
        if let post = WhisperSharedPostEmbed.decode(trimmed) {
            let isWave = post.isReel == true || post.isVideo
            let caption = WhisperPostMeta.strip(from: post.caption).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            let head = isWave ? "Shared a wave" : "Shared a post"
            let label = caption.isEmpty ? head : "\(head) · \(String(caption.prefix(60)))"
            return WhisperChatQuotePreview(label: label, icon: isWave ? "play.rectangle" : "photo.on.rectangle", thumbnailURL: post.mediaURL.flatMap(URL.init(string:)))
        }
        if let profile = WhisperProfileShareEmbed.decode(trimmed) {
            return WhisperChatQuotePreview(label: "Shared a profile · @\(profile.username)", icon: "person.crop.circle", thumbnailURL: profile.avatarURL.flatMap(URL.init(string:)))
        }
        if trimmed.hasPrefix("::") || trimmed.hasPrefix("{") {
            let p = WhisperInboxView.previewFor(body: trimmed, fallback: "Shared a card")
            let label = p.text.hasPrefix("::") || p.text.hasPrefix("{") ? "Shared a card" : p.text
            return WhisperChatQuotePreview(label: label, icon: p.icon ?? "rectangle.on.rectangle", thumbnailURL: nil)
        }
        if WhisperMeetingService.meetingID(fromText: trimmed) != nil {
            return WhisperChatQuotePreview(label: "Meeting link", icon: "video", thumbnailURL: nil)
        }
        return WhisperChatQuotePreview(label: trimmed, icon: nil, thumbnailURL: nil)
    }

    /// The plain line a message should read as inside a quote — never raw wire.
    static func quoteText(for body: String) -> String {
        preview(for: body).label
    }

    /// Finds the message a quote points at (best effort): the sender's most
    /// recent message whose quote line starts with the quoted text. Cheap for
    /// plain text (a prefix check); only card-looking bodies run the describer.
    static func original(for quote: WhisperGroupReplyQuote, in messages: [WhisperMessageRow]) -> WhisperMessageRow? {
        let name = quote.username.lowercased()
        var needle = quote.text
        if needle.hasSuffix("…") { needle.removeLast() }
        needle = needle.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return nil }
        return messages.last { m in
            guard m.from_username.lowercased() == name else { return false }
            let body = m.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let flat = body.replacingOccurrences(of: "\n", with: " ")
            // Old quotes carried the raw body — still match those.
            if flat.hasPrefix(needle) { return true }
            let special = body.hasPrefix("::") || body.hasPrefix("{") || body.hasPrefix("http")
                || body.hasPrefix("jasper-sticker://") || body.hasPrefix("↩ @")
            guard special else { return false }
            return quoteText(for: body).replacingOccurrences(of: "\"", with: "'").hasPrefix(needle)
        }
    }

    /// Instagram's label above a reply bubble.
    /// - `mine`: the REPLY was sent by me.
    /// - `quotedMine`: the QUOTED message was mine.
    static func label(mine: Bool, quotedMine: Bool, otherName: String) -> String {
        switch (mine, quotedMine) {
        case (true, true): return "You replied to yourself"
        case (true, false): return "You replied"
        case (false, true): return "Replied to you"
        case (false, false): return "Replied to themselves"
        }
    }
}

/// The quoted bubble inside a reply — a lighter copy of the original
/// sender's bubble with a vertical bar on its outer edge (the reference
/// look). A quoted CARD or photo renders as a MINI card (thumbnail or icon +
/// its friendly line) — never the full card. Tap scrolls to the original.
struct WhisperChatReplyQuoteView: View {
    let quote: WhisperGroupReplyQuote
    /// The REPLY is mine (drives which side the bar sits on).
    let mine: Bool
    /// The QUOTED message was mine (drives the fill).
    let quotedMine: Bool
    /// The message the quote points at, when the thread still has it —
    /// drives the mini card for quoted cards and media.
    var original: WhisperMessageRow? = nil
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    @Environment(\.whisperChatAppearance) private var appearance
    @Environment(\.whisperChatDesign) private var design

    /// The mini-card description when the quoted message is a card/photo.
    private var cardPreview: WhisperChatQuotePreview? {
        if let original {
            let p = WhisperChatReply.preview(for: original.body)
            return p.isCard ? p : nil
        }
        // The original isn't loaded — read the quote line itself.
        let t = quote.text
        if t == "Video" || WhisperDMThreadView.videoURL(in: t) != nil {
            return WhisperChatQuotePreview(label: "Video", icon: "play.rectangle", thumbnailURL: nil)
        }
        if t.hasPrefix("::") || t.hasPrefix("{") {
            return WhisperChatQuotePreview(label: "Shared a card", icon: "rectangle.on.rectangle", thumbnailURL: nil)
        }
        if t.hasPrefix("http"), let url = URL(string: t.replacingOccurrences(of: "…", with: "")), WhisperDMThreadView.imageURL(in: url.absoluteString) != nil {
            return WhisperChatQuotePreview(label: "Photo", icon: "photo", thumbnailURL: nil)
        }
        return nil
    }

    private var textColor: Color {
        (design?.palette(colorScheme) ?? appearance.palette(colorScheme)).text(mine: quotedMine)
    }

    private var fill: Color {
        (design?.palette(colorScheme) ?? appearance.palette(colorScheme)).fill(mine: quotedMine)
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                if !mine { bar }
                Group {
                    if let card = cardPreview {
                        miniCard(card)
                    } else {
                        Text(quote.text)
                            .font(.system(size: 15))
                            .foregroundStyle(textColor)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                    }
                }
                .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if mine { bar }
            }
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    /// The mini version of a quoted card: a 40pt thumbnail (or an icon tile)
    /// beside its friendly line — the shape of the card, none of its bulk.
    private func miniCard(_ card: WhisperChatQuotePreview) -> some View {
        HStack(spacing: 10) {
            if let url = card.thumbnailURL {
                Color.clear
                    .frame(width: 40, height: 40)
                    .overlay {
                        WhisperCachedAsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color(.secondarySystemBackground)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if let icon = card.icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(textColor)
                    .frame(width: 36, height: 36)
                    .background(textColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(card.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("Tap to view")
                    .font(.system(size: 11.5))
                    .foregroundStyle(textColor.opacity(0.7))
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 240, alignment: .leading)
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(WhisperTheme.muted(colorScheme).opacity(0.45))
            .frame(width: 3)
    }
}

/// The composer's "Replying to @name" strip — sits above the field while a
/// reply is armed; ✕ clears it.
struct WhisperChatReplyStrip: View {
    let name: String
    let preview: String
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.whisperChatAppearance) private var appearance
    @Environment(\.whisperChatDesign) private var design
    private var palette: WhisperChatPalette { design?.palette(colorScheme) ?? appearance.palette(colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(WhisperTheme.ink(colorScheme).opacity(0.55))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to \(name)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(preview)
                    .font(.system(size: 12.5))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(width: 28, height: 28)
                    .background(WhisperTheme.card(colorScheme), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(WhisperTheme.surface(colorScheme))
        .overlay(alignment: .top) {
            Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5)
        }
    }
}

// MARK: - Attach tray

/// One tile in the attach tray.
struct WhisperChatAttachItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    /// Draw the Jasper icon instead of an SF Symbol.
    var jasper: Bool = false
    /// Tiles that open a second level instead of acting immediately.
    var children: [WhisperChatAttachItem] = []
    var action: () -> Void = {}
}

/// The attach tray — a sheet with a grid of squircle tiles (photo, GIF,
/// stickers, Jasper…) in place of a system menu. Tiles with children swap
/// the grid for a list (with a back chevron). Shared by DMs, groups, Jasper.
struct WhisperChatAttachTray: View {
    let title: String
    let items: [WhisperChatAttachItem]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var openGroup: WhisperChatAttachItem?

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 16).padding(.top, 14)
            ScrollView {
                Group {
                    if let group = openGroup { list(group) }
                    else { grid }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .presentationBackground(WhisperTheme.surface(colorScheme))
        .whisperEdgeBack(isEnabled: openGroup != nil) { openGroup = nil }
        .animation(WhisperChatStyle.spring, value: openGroup?.id)
        .presentationDetents([.height(openGroup == nil ? trayHeight : 360), .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private var trayHeight: CGFloat {
        let rows = Int(ceil(Double(items.count) / 4.0))
        return CGFloat(64 + rows * 104)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if openGroup != nil {
                Button {
                    Haptics.tap()
                    openGroup = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: 30, height: 30)
                        .background(WhisperTheme.card(colorScheme), in: Circle())
                        .frame(width: 44, height: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Text(openGroup?.title ?? title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ink)
            Spacer()
        }
        .padding(.bottom, 12)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
            ForEach(items) { item in
                tile(item)
            }
        }
    }

    private func tile(_ item: WhisperChatAttachItem) -> some View {
        Button {
            Haptics.tap()
            if item.children.isEmpty {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { item.action() }
            } else {
                openGroup = item
            }
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(WhisperTheme.card(colorScheme))
                        .frame(width: 58, height: 58)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                        }
                    if item.jasper {
                        Image(systemName: "sparkles")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(WhisperBrandGradient.diagonal)
                    } else {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(ink)
                    }
                }
                Text(item.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func list(_ group: WhisperChatAttachItem) -> some View {
        VStack(spacing: 0) {
            ForEach(group.children) { child in
                Button {
                    Haptics.tap()
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { child.action() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: child.systemImage)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(ink)
                            .frame(width: 36, height: 36)
                            .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        Text(child.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(muted)
                    }
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if child.id != group.children.last?.id {
                    Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5)
                }
            }
        }
    }
}
