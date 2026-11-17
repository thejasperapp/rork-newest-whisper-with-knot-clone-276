import SwiftUI
import UIKit
import AVKit

/// The full cinema experience for a Whisper film — structured exactly like
/// YouTube's watch page: video pinned to the top, bold title, a one-line meta
/// row ("@director · likes · length · date · …more"), the channel row
/// (avatar + Subscribe pill + circular like/dislike/share/comment buttons),
/// a collapsed comments teaser that opens a half sheet, then an Up Next rail
/// of other films. The scrubber, knob, and transport wear Jasper's ghost
/// mint. Rotating the phone sideways takes the player full-screen (the rest
/// of the app stays portrait — this screen widens
/// `AppDelegate.orientationLock` while it's up).
struct WhisperFilmDetailView: View {
    @Environment(\.dismiss) private var dismiss

    /// Mutable — tapping an Up Next film swaps the theater in place.
    @State private var film: WhisperFeedFilm
    /// Optional clip start (seconds) — consumed once by the FIRST film only.
    @State private var pendingStartAt: Int?

    @State private var engagement = WhisperFilmEngagementService.shared

    // Player state
    @State private var player: AVPlayer = AVPlayer()
    @State private var isPlaying: Bool = false
    @State private var isMuted: Bool = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var bufferedTime: Double = 0
    @State private var isBuffering: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var scrubTarget: Double = 0
    @State private var showControls: Bool = true
    @State private var skipFlash: String?
    @State private var timeObserver: Any?
    @State private var endObserver: Any?
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var showShare: Bool = false

    // Watch-page state
    @State private var descriptionExpanded: Bool = false
    @State private var showComments: Bool = false
    @State private var upNext: [WhisperFeedFilm] = []
    @State private var isSubscribed: Bool = false

    // Comments state
    @State private var commentText: String = ""
    @State private var replyTarget: WhisperFilmCommentRow?
    @State private var sendingComment: Bool = false
    @FocusState private var composerFocused: Bool

    /// Jasper's ghost mint — the scrubber/transport brand color.
    private static let mint = WhisperEmberPillPalette.glow
    /// Brighter mint for the knob so it pops on dark frames.
    private static let mintBright = Color(red: 0.49, green: 0.92, blue: 0.77)

    init(film: WhisperFeedFilm, startAt: Int? = nil) {
        _film = State(initialValue: film)
        _pendingStartAt = State(initialValue: startAt)
    }

    private var directorName: String {
        film.director_name ?? film.director_username ?? "Whisper Studios"
    }

    private var reactions: WhisperFilmReactions {
        engagement.reactionsByFilm[film.id] ?? WhisperFilmReactions()
    }

    private var commentCount: Int {
        engagement.commentsByFilm[film.id]?.count ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            Group {
                if landscape {
                    // Rotated → the film IS the screen.
                    playerSurface(fullBleed: true)
                        .ignoresSafeArea()
                } else {
                    portraitLayout
                }
            }
            .background(Color.black.ignoresSafeArea())
            .statusBarHidden(landscape)
            .persistentSystemOverlays(landscape ? .hidden : .automatic)
        }
        .task {
            await engagement.refresh(filmID: film.id)
            refreshSubscribeState()
            upNext = await WhisperStudioService.shared.fetchFeedFilms()
        }
        .onAppear {
            startPlayback()
            // Allow rotation while the theater is up — everything else in the
            // app stays portrait on iPhone.
            AppDelegate.orientationLock = .allButUpsideDown
            Self.refreshSupportedOrientations()
        }
        .onDisappear {
            stopPlayback()
            AppDelegate.orientationLock = .portrait
            Self.requestOrientation(.portrait)
        }
        .sheet(isPresented: $showShare) {
            WhisperContentShareSheet(
                kicker: "WHISPER FILM",
                title: film.title,
                subtitle: "A \(directorName) film",
                imageURL: film.poster_url.flatMap(URL.init(string:)),
                embedBody: filmEmbedLine,
                linkURL: shareURL,
                onRepost: {
                    // The composer presents from the root — close the theater
                    // first, then open it prefilled with the film card.
                    let draft = filmEmbedLine
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        WhisperEmberActionRouter.shared.openComposer(draft: draft)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showComments) {
            commentsSheet
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(red: 0.08, green: 0.08, blue: 0.09))
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Portrait (YouTube watch page)

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            theaterTopBar

            // The video sits right below the brand bar — edge to edge.
            playerSurface(fullBleed: false)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock
                    if descriptionExpanded {
                        descriptionCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    channelRow
                    commentsTeaser
                    upNextSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
            .animation(.whisperSnappy, value: descriptionExpanded)
        }
    }

    /// Slim branded chrome above the player — the Whisper wordmark keeps the
    /// top edge from feeling abruptly cut off, and the close button stays
    /// reachable even while the player controls are hidden.
    private var theaterTopBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close film")
            Spacer(minLength: 0)
        }
        .overlay {
            HStack(spacing: 7) {
                WhisperWordmark(size: 15)
                    .environment(\.colorScheme, .dark)
                Text("FILMS")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2.4)
                    .foregroundStyle(Self.mintBright)
                    .padding(.top, 3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Whisper Films")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .background(Color.black)
    }

    /// The `::whisper-film-v1::` line — the DM body / wall-post draft.
    private var filmEmbedLine: String {
        WhisperFilmEmbed.encode(.init(
            id: film.id,
            title: film.title,
            director: directorName,
            poster: film.poster_url,
            duration: film.duration_seconds
        ))
    }

    // MARK: - Player surface (shared portrait/landscape)

    private func playerSurface(fullBleed: Bool) -> some View {
        ZStack {
            Color(white: 0.03)
            if URL(string: film.video_url) != nil {
                WhisperFilmPlayerLayer(player: player)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "film.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Film unavailable")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            // Double-tap seek zones (single tap toggles the controls).
            HStack(spacing: 0) {
                seekZone(back: true)
                seekZone(back: false)
            }

            if let skipFlash {
                Text(skipFlash)
                    .font(.caption.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .allowsHitTesting(false)
            }

            if isBuffering && isPlaying && !showControls {
                ProgressView()
                    .tint(Self.mintBright)
                    .scaleEffect(1.15)
                    .allowsHitTesting(false)
            }

            // Controls overlay — tap the stage to toggle.
            if showControls {
                controlsOverlay(fullBleed: fullBleed)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showControls)
        .animation(.easeInOut(duration: 0.2), value: skipFlash)
    }

    /// Half-stage tap target: double-tap seeks ±10s, single tap toggles
    /// the controls — the double-tap recognizer defers the single tap.
    private func seekZone(back: Bool) -> some View {
        Color.clear
            .contentShape(.rect)
            .onTapGesture(count: 2) {
                Haptics.tap()
                skip(by: back ? -10 : 10)
                flashSkip(back ? "−10s" : "+10s")
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) { showControls.toggle() }
                if showControls { scheduleControlsHide() }
            }
    }

    private func controlsOverlay(fullBleed: Bool) -> some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.45), .black.opacity(0.0), .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Top row — close floats over the film; studio kicker centered.
            VStack {
                HStack {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.black.opacity(0.45), in: Circle())
                            .overlay { Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    Spacer()
                    Text("WHISPER STUDIOS")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    // Balance the close button so the kicker stays centered.
                    Color.clear.frame(width: 32, height: 32)
                }
                Spacer()
            }
            .padding(.horizontal, fullBleed ? 24 : 12)
            .padding(.top, fullBleed ? 14 : 10)

            // Center transport cluster — or the buffering pulse.
            if isBuffering && isPlaying {
                ProgressView()
                    .tint(Self.mintBright)
                    .scaleEffect(1.2)
            } else {
                HStack(spacing: 34) {
                    transportSkipButton(back: true)
                    Button {
                        Haptics.tap()
                        togglePlay()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 23, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 62, height: 62)
                            .background(
                                LinearGradient(
                                    colors: [Self.mintBright, Self.mint],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                in: Circle()
                            )
                            .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1) }
                            .shadow(color: Self.mint.opacity(0.5), radius: 14, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")
                    transportSkipButton(back: false)
                }
            }

            // Bottom glass control bar: mint scrubber · time · mute · fullscreen.
            VStack {
                Spacer()
                VStack(spacing: 6) {
                    scrubber
                    HStack(spacing: 10) {
                        Text(Self.timecode(isScrubbing ? scrubTarget : currentTime))
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Self.mintBright)
                        Text("/ \(Self.timecode(duration))")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer(minLength: 0)
                        Button {
                            Haptics.tap()
                            isMuted.toggle()
                            player.isMuted = isMuted
                            scheduleControlsHide()
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 27, height: 27)
                                .background(.white.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                        Button {
                            Haptics.tap()
                            Self.requestOrientation(fullBleed ? .portrait : .landscapeRight)
                        } label: {
                            Image(systemName: fullBleed
                                ? "arrow.down.right.and.arrow.up.left"
                                : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 27, height: 27)
                                .background(.white.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(fullBleed ? "Exit fullscreen" : "Fullscreen")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 9)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
                .background(.black.opacity(0.22), in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
                .padding(.horizontal, fullBleed ? 24 : 10)
                .padding(.bottom, fullBleed ? 16 : 10)
            }
        }
    }

    private func transportSkipButton(back: Bool) -> some View {
        Button {
            Haptics.tap()
            skip(by: back ? -10 : 10)
        } label: {
            Image(systemName: back ? "gobackward.10" : "goforward.10")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.38), in: Circle())
                .overlay { Circle().strokeBorder(Self.mint.opacity(0.45), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(back ? "Back 10 seconds" : "Forward 10 seconds")
    }

    private var scrubber: some View {
        GeometryReader { geo in
            let total = max(duration, 0.01)
            let shown = isScrubbing ? scrubTarget : currentTime
            let fraction = CGFloat(min(1, max(0, shown / total)))
            let buffered = CGFloat(min(1, max(0, bufferedTime / total)))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                    .frame(height: 4)
                // Buffered range — mint-washed.
                Capsule().fill(Self.mint.opacity(0.30))
                    .frame(width: max(0, geo.size.width * buffered), height: 4)
                // Played range — Jasper's ghost mint.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Self.mint, Self.mintBright],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * fraction), height: 4)
                // Moment markers — the timestamped moments live ON the timeline.
                ForEach(engagement.timestampsByFilm[film.id] ?? []) { stamp in
                    let f = CGFloat(min(1, max(0, Double(stamp.time_seconds) / total)))
                    Circle()
                        .fill(.white.opacity(0.95))
                        .frame(width: 4.5, height: 4.5)
                        .overlay { Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.5) }
                        .offset(x: max(0, geo.size.width * f - 2.25))
                        .allowsHitTesting(false)
                }
                // Knob — bright mint with a soft glow; grows while scrubbing.
                Circle()
                    .fill(Self.mintBright)
                    .frame(width: isScrubbing ? 15 : 10, height: isScrubbing ? 15 : 10)
                    .shadow(color: Self.mint.opacity(0.9), radius: isScrubbing ? 6 : 4)
                    .offset(x: max(0, geo.size.width * fraction - (isScrubbing ? 7.5 : 5)))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        isScrubbing = true
                        controlsHideTask?.cancel()
                        let f = min(1, max(0, v.location.x / geo.size.width))
                        scrubTarget = Double(f) * total
                    }
                    .onEnded { _ in
                        let target = scrubTarget
                        player.seek(
                            to: CMTime(seconds: target, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                        currentTime = target
                        isScrubbing = false
                        scheduleControlsHide()
                    }
            )
        }
        .frame(height: 22)
        .animation(.easeInOut(duration: 0.15), value: isScrubbing)
    }

    private func flashSkip(_ label: String) {
        skipFlash = label
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            await MainActor.run {
                if skipFlash == label { skipFlash = nil }
            }
        }
    }

    private func skip(by delta: Double) {
        let cap = duration > 0 ? max(0, duration - 0.5) : .greatestFiniteMagnitude
        let target = min(max(0, currentTime + delta), cap)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = target
        scheduleControlsHide()
    }

    /// Fades the controls out after 3s of playback — any interaction re-arms.
    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        guard isPlaying else { return }
        controlsHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if isPlaying && !isScrubbing {
                    withAnimation(.easeInOut(duration: 0.25)) { showControls = false }
                }
            }
        }
    }

    // MARK: - Title + meta line (YouTube style)

    private var hasDescription: Bool {
        (film.synopsis?.isEmpty == false)
            || !(engagement.timestampsByFilm[film.id] ?? []).isEmpty
            || film.featured_date != nil
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(film.title)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            // "@director · 7.2K likes · 12:40 · Jun 6 …more" — one muted line.
            Button {
                guard hasDescription else { return }
                Haptics.tap()
                withAnimation(.whisperSnappy) { descriptionExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(metaLineText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    if hasDescription {
                        Text(descriptionExpanded ? "less" : "\u{2026}more")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(descriptionExpanded ? "Hide description" : "Show description")
        }
    }

    private var metaLineText: String {
        var parts: [String] = []
        if let username = film.director_username, !username.isEmpty {
            parts.append("@\(username)")
        } else {
            parts.append(directorName)
        }
        parts.append("\(reactions.likes) like\(reactions.likes == 1 ? "" : "s")")
        if let secs = film.duration_seconds, secs > 0 {
            parts.append(FeedFilmsCarousel.formatTimecode(secs))
        }
        if let date = film.featured_date, !date.isEmpty, let parsed = Self.parseDate(date) {
            parts.append(parsed.formatted(.dateTime.month(.abbreviated).day()))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Expanded description — synopsis, the featured line, and the
    /// tap-to-seek moments rail (YouTube's expanded description box).
    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = film.synopsis, !s.isEmpty {
                Text(s)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Text("FEATURED FILM")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(Self.mintBright.opacity(0.9))
                if let date = film.featured_date, !date.isEmpty, let parsed = Self.parseDate(date) {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.4))
                    Text(parsed, style: .date)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            momentsRail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
    }

    // MARK: - Channel row (avatar · Subscribe · circular actions)

    private var isMyFilm: Bool {
        guard let id = film.director_id else { return false }
        return id == AccountStorage.currentUserID
    }

    private var channelRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                // Channel chip — tap opens the director's profile.
                Button {
                    openDirectorProfile()
                } label: {
                    HStack(spacing: 8) {
                        WhisperAvatar(username: film.director_username ?? directorName, size: 34)
                        Text(directorName)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(film.director_username == nil)

                if film.director_id != nil && !isMyFilm {
                    subscribeButton
                }

                Spacer(minLength: 2)

                circleAction(
                    icon: reactions.mine == "like" ? "hand.thumbsup.fill" : "hand.thumbsup",
                    active: reactions.mine == "like",
                    label: "Like"
                ) {
                    Haptics.tap()
                    Task { await engagement.setReaction(filmID: film.id, weight: "like") }
                }
                circleAction(
                    icon: reactions.mine == "dislike" ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                    active: reactions.mine == "dislike",
                    label: "Dislike"
                ) {
                    Haptics.tap()
                    Task { await engagement.setReaction(filmID: film.id, weight: "dislike") }
                }
                circleAction(icon: "arrowshape.turn.up.right.fill", label: "Share") {
                    Haptics.tap()
                    showShare = true
                }
                circleAction(icon: "text.bubble.fill", label: "Comments") {
                    Haptics.tap()
                    showComments = true
                }

                Menu {
                    Button {
                        UIPasteboard.general.string = shareURL.absoluteString
                        Haptics.success()
                    } label: {
                        Label("Copy link", systemImage: "link")
                    }
                    if film.director_username != nil {
                        Button {
                            openDirectorProfile()
                        } label: {
                            Label("Go to director", systemImage: "person.crop.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .accessibilityLabel("More actions")
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private var subscribeButton: some View {
        Button {
            toggleSubscribe()
        } label: {
            HStack(spacing: 5) {
                if isSubscribed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                }
                Text(isSubscribed ? "Subscribed" : "Subscribe")
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(isSubscribed ? .white.opacity(0.85) : .black)
            .padding(.horizontal, 15)
            .frame(height: 36)
            .background(
                isSubscribed ? AnyShapeStyle(Color.white.opacity(0.12)) : AnyShapeStyle(Color.white),
                in: Capsule()
            )
            .overlay {
                if isSubscribed {
                    Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.whisperSnappy, value: isSubscribed)
        .accessibilityLabel(isSubscribed ? "Subscribed to \(directorName)" : "Subscribe to \(directorName)")
    }

    private func circleAction(
        icon: String,
        active: Bool = false,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(active ? .black : .white)
                .frame(width: 40, height: 40)
                .background(
                    active ? AnyShapeStyle(Self.mint) : AnyShapeStyle(Color.white.opacity(0.10)),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .animation(.whisperSnappy, value: active)
        .accessibilityLabel(label)
    }

    private func openDirectorProfile() {
        guard let username = film.director_username, !username.isEmpty else { return }
        Haptics.tap()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: .whisperOpenUserByUsername,
                object: nil,
                userInfo: ["username": username]
            )
        }
    }

    private func refreshSubscribeState() {
        guard let id = film.director_id else {
            isSubscribed = false
            return
        }
        isSubscribed = WhisperFollowService.shared.isFollowing(userID: id)
    }

    private func toggleSubscribe() {
        guard let id = film.director_id else { return }
        let username = film.director_username ?? directorName
        if isSubscribed {
            Haptics.tap()
            isSubscribed = false
            Task { _ = await WhisperFollowService.shared.unfollow(userID: id) }
        } else {
            Haptics.success()
            isSubscribed = true
            Task { _ = await WhisperFollowService.shared.follow(userID: id, username: username) }
        }
    }

    // MARK: - Moments rail

    @ViewBuilder
    private var momentsRail: some View {
        let stamps = engagement.timestampsByFilm[film.id] ?? []
        if !stamps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("MOMENTS")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stamps) { stamp in
                            Button {
                                Haptics.tap()
                                seek(to: Double(stamp.time_seconds))
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(Self.mintBright)
                                    Text(Self.timecode(Double(stamp.time_seconds)))
                                        .font(.caption2.weight(.black))
                                        .monospacedDigit()
                                    Text(stamp.label)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Color.white.opacity(0.08), in: Capsule())
                                .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
    }

    // MARK: - Comments teaser (collapsed card → half sheet)

    private var commentsTeaser: some View {
        Button {
            Haptics.tap()
            showComments = true
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Text("Comments")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    if commentCount > 0 {
                        Text("\(commentCount)")
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                if let first = engagement.threadedComments(filmID: film.id).first?.root {
                    HStack(alignment: .top, spacing: 8) {
                        WhisperAvatar(username: engagement.handle(for: first.user_id), size: 24)
                        Text(first.body)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                } else {
                    Text("Be the first to talk about this film")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(13)
            .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open comments. \(commentCount) comments.")
    }

    private var commentsSheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("Comments")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                if commentCount > 0 {
                    Text("\(commentCount)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button {
                    Haptics.tap()
                    showComments = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close comments")
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    let threads = engagement.threadedComments(filmID: film.id)
                    if threads.isEmpty {
                        VStack(spacing: 5) {
                            WhisperMeetDoodle(symbol: "bubble.left.and.bubble.right", height: 96)
                                .environment(\.colorScheme, .dark)
                            Text("Be the first to talk about this film")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        ForEach(threads, id: \.root.id) { thread in
                            commentRow(thread.root, isReply: false)
                            ForEach(thread.replies) { reply in
                                commentRow(reply, isReply: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }

            composer
        }
        .preferredColorScheme(.dark)
    }

    private func commentRow(_ comment: WhisperFilmCommentRow, isReply: Bool) -> some View {
        let handle = engagement.handle(for: comment.user_id)
        let isMine = comment.user_id == AccountStorage.currentUserID
        return HStack(alignment: .top, spacing: 10) {
            WhisperAvatar(username: handle, size: isReply ? 26 : 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("@\(handle)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                    Text(WhisperPost.relativeTime(from: comment.created_at))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text(comment.body)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                if !isReply {
                    Button {
                        Haptics.tap()
                        replyTarget = comment
                        composerFocused = true
                    } label: {
                        Text("Reply")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, isReply ? 36 : 0)
        .contextMenu {
            if isMine {
                Button(role: .destructive) {
                    Haptics.warning()
                    Task { await engagement.deleteComment(id: comment.id, filmID: film.id) }
                } label: {
                    Label("Delete comment", systemImage: "trash")
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let target = replyTarget {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption2.weight(.bold))
                    Text("Replying to @\(engagement.handle(for: target.user_id))")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        Haptics.tap()
                        replyTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $commentText,
                    prompt: Text("Add a comment…").foregroundStyle(.white.opacity(0.4)),
                    axis: .vertical
                )
                .lineLimit(1...4)
                .font(.subheadline)
                .foregroundStyle(.white)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
                Button {
                    sendComment()
                } label: {
                    Group {
                        if sendingComment {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(Self.mint, in: Circle())
                    .opacity(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sendingComment)
                .accessibilityLabel("Send comment")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.10)).frame(height: 0.5)
        }
    }

    private func sendComment() {
        let body = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sendingComment else { return }
        sendingComment = true
        let replyID = replyTarget?.id
        Task {
            let ok = await engagement.addComment(filmID: film.id, body: body, replyTo: replyID)
            await MainActor.run {
                sendingComment = false
                if ok {
                    Haptics.success()
                    commentText = ""
                    replyTarget = nil
                    composerFocused = false
                } else {
                    Haptics.warning()
                }
            }
        }
    }

    // MARK: - Up next (YouTube's watch feed)

    @ViewBuilder
    private var upNextSection: some View {
        let others = upNext.filter { $0.id != film.id }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("UP NEXT")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))
                VStack(spacing: 18) {
                    ForEach(others.prefix(8)) { next in
                        upNextRow(next)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func upNextRow(_ next: WhisperFeedFilm) -> some View {
        Button {
            playFilm(next)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                // Poster — Color anchors the layout, image overlays and clips.
                Color(white: 0.08)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        if let poster = next.poster_url, let url = URL(string: poster) {
                            WhisperCachedAsyncImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    Image(systemName: "film.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white.opacity(0.25))
                                }
                            }
                            .allowsHitTesting(false)
                        } else {
                            Image(systemName: "film.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.25))
                        }
                    }
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay(alignment: .bottomTrailing) {
                        if let secs = next.duration_seconds, secs > 0 {
                            Text(FeedFilmsCarousel.formatTimecode(secs))
                                .font(.caption2.weight(.black))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.75), in: .rect(cornerRadius: 6))
                                .padding(7)
                        }
                    }
                    .overlay(alignment: .center) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.45), in: Circle())
                            .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
                    }

                HStack(alignment: .top, spacing: 10) {
                    WhisperAvatar(
                        username: next.director_username ?? next.director_name ?? "Whisper Studios",
                        size: 30
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(upNextMetaText(next))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Long-press peek — quick actions without leaving the current film.
        .contextMenu {
            Button {
                playFilm(next)
            } label: {
                Label("Play now", systemImage: "play.fill")
            }
            Button {
                playFilm(next)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    showShare = true
                }
            } label: {
                Label("Play & share", systemImage: "square.and.arrow.up")
            }
        }
        .accessibilityLabel("Play \(next.title)")
    }

    private func upNextMetaText(_ next: WhisperFeedFilm) -> String {
        var parts: [String] = [next.director_name ?? next.director_username ?? "Whisper Studios"]
        if let date = next.featured_date, !date.isEmpty, let parsed = Self.parseDate(date) {
            parts.append(parsed.formatted(.dateTime.month(.abbreviated).day()))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Swaps the theater to another film in place — player, engagement,
    /// subscribe state, and description all reset for the new pick.
    private func playFilm(_ next: WhisperFeedFilm) {
        guard next.id != film.id else { return }
        Haptics.tap()
        stopPlayback()
        film = next
        currentTime = 0
        duration = 0
        bufferedTime = 0
        descriptionExpanded = false
        replyTarget = nil
        showControls = true
        startPlayback()
        refreshSubscribeState()
        Task { await engagement.refresh(filmID: next.id) }
    }

    // MARK: - Orientation plumbing

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// Re-evaluates `AppDelegate.orientationLock` without forcing a rotation.
    private static func refreshSupportedOrientations() {
        activeWindowScene()?.keyWindow?.rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    /// Actively rotates the interface (fullscreen button / dismiss snap-back).
    private static func requestOrientation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = activeWindowScene() else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        refreshSupportedOrientations()
    }

    // MARK: - Playback plumbing

    private func startPlayback() {
        guard let url = URL(string: film.video_url) else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = isMuted
        if let startAt = pendingStartAt, startAt > 0 {
            player.seek(to: CMTime(seconds: Double(startAt), preferredTimescale: 600))
            currentTime = Double(startAt)
        }
        pendingStartAt = nil
        player.play()
        isPlaying = true

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { time in
            Task { @MainActor in
                if !isScrubbing { currentTime = time.seconds }
                if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                    duration = d
                }
                if let range = player.currentItem?.loadedTimeRanges.last?.timeRangeValue {
                    bufferedTime = range.start.seconds + range.duration.seconds
                }
                isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
        scheduleControlsHide()

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
    }

    private func stopPlayback() {
        player.pause()
        controlsHideTask?.cancel()
        if let token = timeObserver {
            player.removeTimeObserver(token)
            timeObserver = nil
        }
        if let token = endObserver {
            NotificationCenter.default.removeObserver(token)
            endObserver = nil
        }
    }

    private func togglePlay() {
        if isPlaying {
            player.pause()
            controlsHideTask?.cancel()
        } else {
            player.play()
        }
        isPlaying.toggle()
        if isPlaying { scheduleControlsHide() }
    }

    private func seek(to seconds: Double) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = seconds
        if !isPlaying { togglePlay() }
    }

    private var shareURL: URL {
        URL(string: "\(WhisperBillingBackend.webOrigin)/films/\(film.id)")
            ?? URL(string: "https://www.mydailywhisper.com")!
    }

    private static func parseDate(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)
    }

    private static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return FeedFilmsCarousel.formatTimecode(Int(seconds.rounded()))
    }
}

/// Chrome-free AVPlayer surface — the stage draws its own controls, so the
/// system `VideoPlayer` chrome would fight the custom scrubber.
private struct WhisperFilmPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
