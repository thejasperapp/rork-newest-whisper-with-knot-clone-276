import SwiftUI

/// Tucked under the owner's avatar — a small Story-viewers-style row of
/// overlapping mini-avatars showing the most recent repliers, plus a soft
/// pulsing accent dot when there's unread activity. No number badge: the
/// count surfaces inside the sheet itself as a fading "X new" chip so the
/// profile stays calm.
struct WhisperThoughtRepliesBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var service = WhisperThoughtRepliesService.shared
    @State private var presentSheet: Bool = false
    @State private var pulse: Bool = false

    /// Up to three most-recent unique repliers, newest first.
    private var avatars: [WhisperThoughtReplyRow] {
        var seen: Set<String> = []
        var out: [WhisperThoughtReplyRow] = []
        for row in service.incoming {
            let key = row.replier_user_id.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(row)
            if out.count >= 3 { break }
        }
        return out
    }

    private var hasUnread: Bool { service.unreadCount > 0 }

    var body: some View {
        Group {
            if !service.incoming.isEmpty {
                Button {
                    Haptics.tap()
                    presentSheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        HStack(spacing: -8) {
                            ForEach(avatars.reversed(), id: \.id) { row in
                                avatar(for: row)
                            }
                        }
                        if hasUnread {
                            pulsingDot
                                .offset(x: 4, y: -2)
                        }
                    }
                    .accessibilityLabel(
                        "\(service.incoming.count) replies to your thought\(hasUnread ? ", new" : "")"
                    )
                }
                .buttonStyle(.plain)
                .task { await service.refreshForMe() }
                .onAppear { pulse = true }
            }
        }
        .sheet(isPresented: $presentSheet) {
            WhisperThoughtRepliesSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(22)
                .whisperSheetBorder()
        }
    }

    private func avatar(for row: WhisperThoughtReplyRow) -> some View {
        let url = row.replier_avatar_url.flatMap { URL(string: $0) }
        return WhisperCachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            default:
                Circle()
                    .fill(WhisperTheme.card(colorScheme))
                    .overlay {
                        Text(String(row.replier_username.prefix(1)).uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 2)
        }
    }

    /// Soft pulsing dot in the system accent — only appears when there are
    /// unread replies. Pulse is gentle (scale + opacity) so it reads as
    /// "still going" rather than an alert badge.
    private var pulsingDot: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 14, height: 14)
                .scaleEffect(pulse ? 1.0 : 0.6)
                .opacity(pulse ? 0.0 : 0.7)
                .animation(
                    .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                    value: pulse
                )
            Circle()
                .fill(Color.accentColor)
                .frame(width: 7, height: 7)
                .overlay {
                    Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 1.5)
                }
        }
    }
}

/// Expandable community-chat sheet for every reply to the owner's active
/// thought. Renders the pinned thought at the top and the rest of the
/// conversation chronologically — like a small group chat where the owner
/// and every replier are all in the same room.
struct WhisperThoughtRepliesSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var service = WhisperThoughtRepliesService.shared
    @State private var thoughts = WhisperThoughtService.shared
    @State private var draft: String = ""
    @State private var sending: Bool = false
    @State private var showNewChip: Bool = false
    @State private var newCount: Int = 0
    @FocusState private var composerFocused: Bool
    /// A post or wave shared INTO the room, tapped — opens the real post.
    @State private var sharedPostDetail: WhisperSharedPostEmbed.Payload?
    /// The "+" share picker — the room owner's posts and yours.
    @State private var showSharePicker: Bool = false

    /// When non-nil, the sheet opens the group chat for someone else's
    /// thought (replier-side). When nil, it shows the current user's own
    /// thought chat (owner-side).
    let externalOwnerUID: String?
    let externalOwnerUsername: String?

    init(externalOwnerUID: String? = nil, externalOwnerUsername: String? = nil) {
        self.externalOwnerUID = externalOwnerUID
        self.externalOwnerUsername = externalOwnerUsername
    }

    /// Live session UID — used to right-align the owner's own messages.
    private var myUID: String { service.mySessionUIDLower }

    private var isExternal: Bool { externalOwnerUID != nil }

    /// Rows powering the chat — either my incoming replies (owner mode)
    /// or the cached group rows for someone else's thought (replier mode).
    private var rows: [WhisperThoughtReplyRow] {
        if let uid = externalOwnerUID?.lowercased() {
            return service.groupByOwner[uid] ?? []
        }
        return service.incoming
    }

    /// Newest-first from the service; flip to chronological for chat reading.
    private var chronological: [WhisperThoughtReplyRow] {
        rows.sorted { ($0.created_at ?? "") < ($1.created_at ?? "") }
    }

    /// Unique participants for the header count chip.
    private var participantCount: Int {
        var seen = Set<String>()
        for r in rows { seen.insert(r.replier_user_id.lowercased()) }
        if let uid = externalOwnerUID?.lowercased() {
            seen.insert(uid)
        }
        seen.insert(myUID)
        return seen.count
    }

    /// The thought to pin at the top. Prefer the live thought (owner mode);
    /// fall back to the snapshot stored on the most recent row.
    private var pinnedThought: (text: String, style: WhisperThoughtStyle, accent: String, emoji: String, colorHex: String)? {
        if !isExternal, thoughts.isActive, !thoughts.text.isEmpty {
            return (thoughts.text, thoughts.style, thoughts.accent, thoughts.emoji, thoughts.colorHex)
        }
        if isExternal, let uid = externalOwnerUID,
           let live = thoughts.activeThought(forUserID: uid) {
            return (
                live.text,
                WhisperThoughtStyle(rawValue: live.style ?? "") ?? .plain,
                live.accent ?? "",
                live.emoji ?? "",
                live.color_hex ?? ""
            )
        }
        if let latest = rows.first, let t = latest.thought_text, !t.isEmpty {
            return (
                t,
                WhisperThoughtStyle(rawValue: latest.thought_style ?? "") ?? .plain,
                latest.thought_accent ?? "",
                latest.thought_emoji ?? "",
                latest.thought_color_hex ?? ""
            )
        }
        return nil
    }

    var body: some View {
            VStack(spacing: 0) {
                pinnedHeader
                themeRule
                if let err = service.lastError, !err.isEmpty {
                    errorBanner(err)
                }
                chatScroll
                Divider().overlay(WhisperTheme.hairline(colorScheme))
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        quickReactionRow
                        composer
                    }
                    if showNewChip && newCount > 0 {
                        newRepliesChip
                            .offset(y: -18)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .background {
                // Whisper-quiet base with a whisper of the room's theme color
                // washed over the whole sheet — each room reads as its own
                // colored space without shouting over the chat.
                ZStack {
                    WhisperTheme.surface(colorScheme)
                    if let t = pinnedThought {
                        WhisperThoughtBubble.bubbleGradient(colorHex: t.colorHex, style: t.style)
                            .opacity(colorScheme == .dark ? 0.10 : 0.05)
                    }
                }
                .ignoresSafeArea()
            }
            .task {
                if let uid = externalOwnerUID {
                    await service.refreshForOwner(uid)
                } else {
                    let unread = service.unreadCount
                    await service.refreshForMe()
                    if unread > 0 {
                        await MainActor.run {
                            newCount = unread
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showNewChip = true
                            }
                        }
                        try? await Task.sleep(for: .seconds(1.4))
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.35)) {
                                showNewChip = false
                            }
                        }
                    }
                    await service.markAllRead()
                }
            }
            .task(id: externalOwnerUID ?? "_self") {
                // Light polling so new replies surface while the sheet is open.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    if Task.isCancelled { break }
                    if let uid = externalOwnerUID {
                        await service.refreshForOwner(uid)
                    } else {
                        await service.refreshForMe()
                    }
                }
            }
    }

    // MARK: Pinned thought header

    /// Thin gradient rule in the room's theme color — replaces the plain
    /// divider under the header so the room's identity underlines the space.
    @ViewBuilder
    private var themeRule: some View {
        if let t = pinnedThought {
            // The room's theme DISSOLVES into the replies instead of stopping
            // at a hard 2pt rule: a soft wash that fades out over ~64pt and
            // tucks under the first rows, so header and room read as one.
            WhisperThoughtBubble.bubbleGradient(colorHex: t.colorHex, style: t.style)
                .frame(height: 64)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.42), location: 0),
                            .init(color: .black.opacity(0.18), location: 0.38),
                            .init(color: .black.opacity(0.05), location: 0.78),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.bottom, -40)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            Divider().overlay(WhisperTheme.hairline(colorScheme))
        }
    }

    @ViewBuilder
    private var pinnedHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Text(isExternal ? "@\(externalOwnerUsername ?? "thought")'s room" : "Your room")
                    .font(.caption.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Spacer()
                participantChip
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 26, height: 26)
                        .background(WhisperTheme.surface(colorScheme).opacity(0.9), in: Circle())
                        .overlay {
                            Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            if let t = pinnedThought {
                HStack(alignment: .center, spacing: 12) {
                    WhisperThoughtBubble(
                        text: t.text,
                        scale: 0.7,
                        style: t.style,
                        accent: t.accent,
                        emoji: t.emoji,
                        colorHex: t.colorHex
                    )
                    Spacer(minLength: 0)
                    if !t.emoji.isEmpty {
                        Text(t.emoji)
                            .font(.system(size: 34))
                            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            } else {
                Text("No active thought right now.")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background {
            // Soft wash of the room's theme color so the header carries the
            // thought's identity. With no navigation bar above it anymore,
            // the wash runs all the way to the very top of the sheet — no
            // abrupt white band under the drag indicator.
            ZStack {
                WhisperTheme.surface(colorScheme)
                if let t = pinnedThought {
                    WhisperThoughtBubble.bubbleGradient(colorHex: t.colorHex, style: t.style)
                        .opacity(colorScheme == .dark ? 0.26 : 0.15)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    /// Overlapping mini-avatars of the most recent repliers + live count —
    /// makes the room read as a shared space at a glance.
    private var participantChip: some View {
        HStack(spacing: 6) {
            if !uniqueRepliers.isEmpty {
                HStack(spacing: -7) {
                    ForEach(uniqueRepliers, id: \.id) { row in
                        miniAvatar(for: row)
                    }
                }
            }
            Text("\(participantCount) here")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(WhisperTheme.surface(colorScheme).opacity(0.9), in: Capsule())
        .overlay {
            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    /// Up to three most-recent unique repliers for the header stack.
    private var uniqueRepliers: [WhisperThoughtReplyRow] {
        var seen: Set<String> = []
        var out: [WhisperThoughtReplyRow] = []
        for row in rows {
            let key = row.replier_user_id.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(row)
            if out.count >= 3 { break }
        }
        return out
    }

    private func miniAvatar(for row: WhisperThoughtReplyRow) -> some View {
        let url = row.replier_avatar_url.flatMap { URL(string: $0) }
        return WhisperCachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            default:
                Circle()
                    .fill(WhisperTheme.card(colorScheme))
                    .overlay {
                        Text(String(row.replier_username.prefix(1)).uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 1.5)
        }
    }

    // MARK: Chat scroll

    @ViewBuilder
    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if chronological.isEmpty {
                        emptyState
                            .padding(.top, 60)
                    } else {
                        ForEach(chronological) { row in
                            chatRow(row)
                                .id(row.id)
                                .transition(
                                    .asymmetric(
                                        insertion: .scale(scale: 0.94, anchor: .bottom)
                                            .combined(with: .opacity),
                                        removal: .opacity
                                    )
                                )
                        }
                    }
                    Color.clear.frame(height: 4).id("_bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .animation(.whisperSmooth, value: chronological.count)
            }
            .onChange(of: chronological.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("_bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("_bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func chatRow(_ row: WhisperThoughtReplyRow) -> some View {
        let mine = row.replier_user_id.lowercased() == myUID
        let theme = pinnedThought
        let themeHex = theme?.colorHex ?? ""
        let themeStyle = theme?.style ?? .plain
        // Mine = filled with the room's theme gradient (so the owner's
        // bubbles carry the thought's color). Others = white card with a
        // subtle accent border so the room still feels like part of the
        // thought, not a generic gray DM thread.
        let mineFill: AnyShapeStyle = AnyShapeStyle(
            WhisperThoughtBubble.bubbleGradient(colorHex: themeHex, style: themeStyle)
        )
        let mineText: Color = WhisperThoughtBubble.bubbleTextColor(
            colorHex: themeHex, style: themeStyle
        )
        let othersFill: AnyShapeStyle = AnyShapeStyle(
            colorScheme == .dark ? Color(white: 0.16) : Color.white
        )
        let othersText: Color = WhisperTheme.ink(colorScheme)
        let hasCustomHex = !themeHex.isEmpty
        let customColor: Color = WhisperThoughtBubble.swatchColor(themeHex)
        let accentBorder: Color = {
            if hasCustomHex { return customColor.opacity(0.45) }
            switch themeStyle {
            case .location: return Color(red: 1.00, green: 0.24, blue: 0.55).opacity(0.45)
            case .music:    return Color(red: 0.48, green: 0.18, blue: 0.97).opacity(0.45)
            case .plain:    return WhisperTheme.hairline(colorScheme)
            }
        }()
        let shadowTint: Color = {
            if hasCustomHex { return customColor.opacity(0.30) }
            switch themeStyle {
            case .location: return Color(red: 1.00, green: 0.24, blue: 0.55).opacity(0.30)
            case .music:    return Color(red: 0.48, green: 0.18, blue: 0.97).opacity(0.30)
            case .plain:    return Color.black.opacity(0.10)
            }
        }()

        return HStack(alignment: .bottom, spacing: 8) {
            if mine { Spacer(minLength: 40) }
            if !mine { avatar(for: row) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if !mine {
                    Text("@\(displayUsername(for: row))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 4)
                }
                // Mini IG-Notes bubble: rounded rect + two tail circles
                // dropping toward the avatar. Tail flips sides based on
                // who sent the message.
                ZStack(alignment: mine ? .bottomTrailing : .bottomLeading) {
                    Group {
                        if let shared = WhisperSharedPostEmbed.decode(row.body) {
                            // A post or wave shared INTO the room — the same card
                            // DMs render, tappable straight to the real post.
                            WhisperSharedPostInlineCard(payload: shared, mine: mine) {
                                Haptics.tap()
                                sharedPostDetail = shared
                            }
                            .padding(4)
                        } else {
                            Text(row.body)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(mine ? mineText : othersText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                    }
                        .background(
                            mine ? mineFill : othersFill,
                            in: .rect(cornerRadius: 18, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    mine ? Color.white.opacity(0.18) : accentBorder,
                                    lineWidth: 0.75
                                )
                        }
                        .shadow(color: shadowTint, radius: 6, x: 0, y: 3)
                    // Two stacked tail dots dropping toward the avatar —
                    // the IG-Notes signature shape that makes every reply
                    // read as a tiny thought bubble.
                    bubbleTail(mine: mine,
                               mineFill: mineFill,
                               othersFill: othersFill,
                               accentBorder: accentBorder)
                        .offset(
                            x: mine ? -8 : 8,
                            y: 12
                        )
                }
            }
            if mine { avatar(for: row) }
            if !mine { Spacer(minLength: 40) }
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    /// Two stacked dots that form the chat-bubble tail — small one further
    /// away, tiny one nearest the avatar. Painted with the same fill +
    /// border as the bubble so the whole shape reads as one thought.
    @ViewBuilder
    private func bubbleTail(
        mine: Bool,
        mineFill: AnyShapeStyle,
        othersFill: AnyShapeStyle,
        accentBorder: Color
    ) -> some View {
        let fill: AnyShapeStyle = mine ? mineFill : othersFill
        let stroke: Color = mine ? Color.white.opacity(0.18) : accentBorder
        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            Circle()
                .fill(fill)
                .frame(width: 8, height: 8)
                .overlay { Circle().strokeBorder(stroke, lineWidth: 0.6) }
            Circle()
                .fill(fill)
                .frame(width: 4, height: 4)
                .overlay { Circle().strokeBorder(stroke, lineWidth: 0.5) }
        }
    }

    /// Username resolver — if the row's stored handle is missing or fell
    /// back to the generic "user" sentinel, attempt to recover the real
    /// handle from the backend's public-profile cache so the bubble never
    /// reads as "@user".
    private func displayUsername(for row: WhisperThoughtReplyRow) -> String {
        let raw = row.replier_username
        if !raw.isEmpty && raw.lowercased() != "user" { return raw }
        let cached = WhisperBackendService.shared
            .resolvedAuthorUsername(rowUsername: nil, rowUserID: row.replier_user_id)
        if !cached.isEmpty, cached.lowercased() != "user" {
            return cached
        }
        // Final fallback: short uid so it's still identifiable.
        return String(row.replier_user_id.prefix(6))
    }

    private func avatar(for row: WhisperThoughtReplyRow) -> some View {
        let url = row.replier_avatar_url.flatMap { URL(string: $0) }
        return WhisperCachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            default:
                Circle()
                    .fill(WhisperTheme.card(colorScheme))
                    .overlay {
                        Text(String(row.replier_username.prefix(1)).uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }

    // MARK: Composer

    @ViewBuilder
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Share a post or wave into the room — the community can pass
            // the owner's work (or their own) around right here.
            Button {
                Haptics.soft()
                showSharePicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(width: 44, height: 44)
                    .modifier(WhisperControlGlass(shape: Circle()))
            }
            .disabled(sending)
            .accessibilityLabel("Share a post to the room")
            TextField("Reply to the room…", text: $draft, axis: .vertical)
                .focused($composerFocused)
                .lineLimit(1...4)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .modifier(WhisperControlGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(sendForeground)
                    .frame(width: 36, height: 36)
                    .background(sendFill, in: Circle())
                    .scaleEffect(canSend ? 1.0 : 0.92)
                    .animation(.whisperSnappy, value: canSend)
            }
            .disabled(!canSend || sending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WhisperTheme.surface(colorScheme))
        .sheet(isPresented: $showSharePicker) {
            WhisperNoteRoomSharePicker(
                ownerUID: externalOwnerUID,
                ownerUsername: externalOwnerUsername
            ) { post in
                Task { await shareToRoom(post) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $sharedPostDetail) { payload in
            WhisperReferencedPostView(postID: payload.postID, focusedCommentID: payload.commentID)
        }
    }

    /// Drops a post/wave into the room as the shared-post card DMs use.
    private func shareToRoom(_ post: WhisperPost) async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        Haptics.tap()
        await deliver(body: WhisperNoteRoomSharePicker.body(for: post))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Send button carries the room's theme gradient when ready — the same
    /// fill as the owner's bubbles, so sending feels like joining the room.
    private var sendFill: AnyShapeStyle {
        if canSend, let t = pinnedThought {
            return AnyShapeStyle(
                WhisperThoughtBubble.bubbleGradient(colorHex: t.colorHex, style: t.style)
            )
        }
        if canSend {
            return AnyShapeStyle(WhisperTheme.ink(colorScheme))
        }
        return AnyShapeStyle(WhisperTheme.muted(colorScheme).opacity(0.4))
    }

    private var sendForeground: Color {
        if canSend, let t = pinnedThought {
            return WhisperThoughtBubble.bubbleTextColor(colorHex: t.colorHex, style: t.style)
        }
        return WhisperTheme.surface(colorScheme)
    }

    private func send() async {
        guard canSend, !sending else { return }
        sending = true
        defer { sending = false }
        let body = draft
        draft = ""
        Haptics.tap()
        await deliver(body: body)
    }

    /// One-tap emoji reply — lands in the room instantly, no typing needed.
    private func sendQuickReaction(_ emoji: String) async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        Haptics.tap()
        await deliver(body: emoji)
    }

    private func deliver(body: String) async {
        let t = pinnedThought
        if let ownerUID = externalOwnerUID {
            _ = await service.send(
                toUserID: ownerUID,
                toUsername: externalOwnerUsername ?? "user",
                thoughtText: t?.text ?? "",
                thoughtStyle: t?.style.rawValue,
                thoughtAccent: t?.accent,
                thoughtEmoji: t?.emoji,
                thoughtColorHex: t?.colorHex,
                body: body
            )
            await service.refreshForOwner(ownerUID)
        } else {
            _ = await service.sendAsOwner(
                body: body,
                thoughtText: t?.text ?? "",
                thoughtStyle: t?.style.rawValue,
                thoughtAccent: t?.accent,
                thoughtEmoji: t?.emoji,
                thoughtColorHex: t?.colorHex
            )
        }
    }

    /// Instant emoji reactions above the composer — the fastest way to
    /// jump into a room without typing.
    private var quickReactionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["❤️", "🔥", "😂", "👏", "💯", "👀"], id: \.self) { emoji in
                    Button {
                        Task { await sendQuickReaction(emoji) }
                    } label: {
                        Text(emoji)
                            .font(.body)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(WhisperTheme.card(colorScheme), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(sending)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 8)
    }

    /// Tiny floating chip pinned above the composer that fades after a
    /// beat — the calm replacement for the in-your-face count badge.
    private var newRepliesChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
            Text("\(newCount) new")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(WhisperTheme.card(colorScheme))
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
        )
        .overlay {
            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    @ViewBuilder
    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            WhisperMeetDoodle(symbol: "bubble.left.and.bubble.right", height: 144)
            Text("Quiet in here")
                .font(.headline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(isExternal ? "Be the first to reply — the conversation lives right here, not in DMs." : "When someone replies to your thought, the conversation lives right here — not in your DMs.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if isExternal {
                // Conversation starters — tap to prefill the composer so
                // joining the room takes one tap instead of a blank box.
                // (Wash color for the icon disc is derived from the room's
                // theme so even the empty state feels like this room.)
                HStack(spacing: 8) {
                    ForEach(["👋 Hey!", "Same here", "Tell me more"], id: \.self) { starter in
                        Button {
                            Haptics.tap()
                            draft = starter
                            composerFocused = true
                        } label: {
                            Text(starter)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(WhisperTheme.card(colorScheme), in: Capsule())
                                .overlay {
                                    Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// Soft disc behind the empty-state icon, tinted with the room's theme.
    private var emptyStateWash: AnyShapeStyle {
        if let t = pinnedThought {
            return AnyShapeStyle(
                WhisperThoughtBubble.bubbleGradient(colorHex: t.colorHex, style: t.style)
                    .opacity(colorScheme == .dark ? 0.35 : 0.22)
            )
        }
        return AnyShapeStyle(WhisperTheme.card(colorScheme))
    }
}
