import SwiftUI
import AVFoundation
import UIKit

// MARK: - The sound model

/// The Sounds system — TikTok / Instagram Reels grammar: EVERY wave carries a
/// sound. Either a catalog track (the iTunes preview the creator picked, as
/// `WhisperStoryMusic`) or the wave's OWN audio — an "original sound" that
/// anyone can reuse. Reuse rides the same `meta.music` caption wire as
/// tracks, with the id `orig:<postID>`, so a wave made with someone's
/// original sound attributes back to them on every platform (web reads the
/// identical field). The loop TikTok runs on: wave → sound page → new waves
/// → more sound-page traffic → more waves.
enum WhisperWaveSound {
    static let originalPrefix = "orig:"

    /// The sound a wave wears: its picked track, else its own original sound.
    static func sound(for post: WhisperPost) -> WhisperStoryMusic {
        if let m = WhisperPostMeta.parse(from: post.caption)?.music, !m.title.isEmpty {
            let fallbackID = "track:\(m.title.lowercased())-\(m.artist.lowercased())"
            return WhisperStoryMusic(
                id: m.id ?? fallbackID,
                title: m.title,
                artist: m.artist,
                artworkURL: m.artworkURL,
                previewURL: m.previewURL ?? ""
            )
        }
        return original(of: post)
    }

    /// A wave's own audio as a reusable sound.
    static func original(of post: WhisperPost) -> WhisperStoryMusic {
        let video = post.mediaURLs.first(where: { WhisperVideo.isVideo($0) })
        let still = post.mediaURLs.first(where: { !WhisperVideo.isVideo($0) })
        return WhisperStoryMusic(
            id: originalPrefix + post.id.uuidString.lowercased(),
            title: "Original sound",
            artist: post.username,
            artworkURL: still?.absoluteString,
            previewURL: video?.absoluteString ?? ""
        )
    }

    static func isOriginal(_ m: WhisperStoryMusic) -> Bool {
        m.id.hasPrefix(originalPrefix)
    }

    /// The source wave id for an original sound.
    static func originalPostID(_ m: WhisperStoryMusic) -> String? {
        guard isOriginal(m) else { return nil }
        return String(m.id.dropFirst(originalPrefix.count))
    }

    /// The attribution line: "Original sound · username" or "Title · Artist".
    static func label(_ m: WhisperStoryMusic) -> String {
        isOriginal(m) ? "Original sound · \(m.artist)" : "\(m.title) · \(m.artist)"
    }

    /// Every wave in `pool` wearing this sound, pool order kept, deduped.
    static func waves(using sound: WhisperStoryMusic, in pool: [WhisperPost]) -> [WhisperPost] {
        var seen = Set<UUID>()
        var out: [WhisperPost] = []
        for p in pool where self.sound(for: p).id == sound.id && !seen.contains(p.id) {
            seen.insert(p.id)
            out.append(p)
        }
        return out
    }

    /// Sounds ranked by how many waves in the pool wear them.
    static func trending(in pool: [WhisperPost], limit: Int = 12) -> [(sound: WhisperStoryMusic, count: Int)] {
        var counts: [String: (WhisperStoryMusic, Int)] = [:]
        for p in pool {
            let s = sound(for: p)
            if let existing = counts[s.id] {
                counts[s.id] = (existing.0, existing.1 + 1)
            } else {
                counts[s.id] = (s, 1)
            }
        }
        return counts.values
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { (sound: $0.0, count: $0.1) }
    }

    /// The caption meta line for a picked sound — the SAME wire the grid
    /// composer and web write, so attribution renders identically everywhere.
    static func metaLine(for music: WhisperStoryMusic) -> String? {
        metaLine(music: music, cover: nil)
    }

    /// The wave's caption meta line — the picked sound, the cover frame URL,
    /// and Instagram's "Also share to feed" flag — on the SAME wire the grid
    /// composer and web write. Returns nil when there's nothing to carry.
    static func metaLine(music: WhisperStoryMusic?, cover: String?, feed: Bool = false) -> String? {
        var meta: [String: Any] = [:]
        if feed { meta["feed"] = true }
        if let music {
            var m: [String: Any] = ["id": music.id, "title": music.title, "artist": music.artist]
            if let art = music.artworkURL { m["artworkURL"] = art }
            m["previewURL"] = music.previewURL
            meta["music"] = m
        }
        if let cover, !cover.isEmpty {
            meta["cover"] = cover
        }
        guard !meta.isEmpty,
              let json = try? JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys]),
              let line = String(data: json, encoding: .utf8) else { return nil }
        return "\(WhisperPostMeta.prefix)\(line)"
    }
}

// MARK: - Saved sounds

/// TikTok's "Add to Favorites" for sounds — kept on-device, newest first.
@MainActor
@Observable
final class WhisperSavedSounds {
    static let shared = WhisperSavedSounds()
    private let key = "whisper.savedSounds.v1"

    private(set) var sounds: [WhisperStoryMusic] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([WhisperStoryMusic].self, from: data) {
            sounds = decoded
        }
    }

    func isSaved(_ m: WhisperStoryMusic) -> Bool {
        sounds.contains { $0.id == m.id }
    }

    func toggle(_ m: WhisperStoryMusic) {
        if let idx = sounds.firstIndex(where: { $0.id == m.id }) {
            sounds.remove(at: idx)
        } else {
            sounds.insert(m, at: 0)
            if sounds.count > 60 { sounds.removeLast(sounds.count - 60) }
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sounds) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Marquee attribution

/// One-line text that glides sideways when it doesn't fit — Instagram's
/// sound line. Sits still when it fits. When it overflows it rests 1.6s at
/// the start, glides to the end, rests 1.2s, then fades back to the start
/// (no endless duplicate-text conveyor), and the visible window fades out at
/// its trailing edge so the cut never reads as a hard chop.
struct WhisperSoundMarquee: View {
    let text: String
    var font: Font = .system(size: 12, weight: .semibold)
    var maxWidth: CGFloat = 170
    /// Points per second.
    var speed: Double = 24

    @State private var textWidth: CGFloat = 0

    private var overflows: Bool { textWidth > maxWidth + 1 }
    private var travel: Double { Double(max(0, textWidth - maxWidth)) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !overflows)) { context in
            let restStart = 1.6
            let restEnd = 1.2
            let glide = travel / speed
            let period = restStart + glide + restEnd + 0.5
            let t = overflows ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) : 0
            let progress: Double = {
                guard overflows else { return 0 }
                if t < restStart { return 0 }
                if t < restStart + glide { return (t - restStart) / max(glide, 0.01) }
                return 1
            }()
            // The 0.5s tail is the fade back to the start.
            let resetting = overflows && t > restStart + glide + restEnd
            let offset = -CGFloat(progress * travel)
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { w in
                    if abs(w - textWidth) > 0.5 { textWidth = w }
                }
                .offset(x: resetting ? 0 : offset)
                .opacity(resetting ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: resetting)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .mask(
                    HStack(spacing: 0) {
                        Color.black
                        if overflows {
                            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 22)
                        }
                    }
                )
        }
        .frame(width: textWidth > 0 ? min(textWidth, maxWidth) : nil)
        .frame(maxWidth: maxWidth)
    }
}

// MARK: - The spinning disc

/// TikTok's vinyl at the foot of the action rail — album art (or the
/// creator's avatar for original sounds) inside a dark record with a white
/// rim, spinning while the wave plays, with two music notes drifting off it.
struct WhisperSoundDisc: View {
    let sound: WhisperStoryMusic
    let username: String
    let spinning: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.20), Color(white: 0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 46, height: 46)
                .overlay { Circle().strokeBorder(.white.opacity(0.92), lineWidth: 1.5) }
            Circle()
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                .frame(width: 38, height: 38)
            Circle()
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                .frame(width: 33, height: 33)
            artwork
                .frame(width: 26, height: 26)
                .clipShape(Circle())
        }
        .shadow(color: .black.opacity(0.5), radius: 5, y: 1)
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .animation(
            spinning
                ? .linear(duration: 6).repeatForever(autoreverses: false)
                : .easeOut(duration: 0.3),
            value: spinning
        )
        .overlay(alignment: .topLeading) {
            if spinning {
                FloatingNote(delay: 0, drift: CGSize(width: -14, height: -34))
                    .offset(x: -6, y: 6)
                FloatingNote(delay: 0.9, drift: CGSize(width: -22, height: -26))
                    .offset(x: -2, y: 14)
            }
        }
        .accessibilityLabel(WhisperWaveSound.label(sound))
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = sound.artworkURL, let url = URL(string: art) {
            WhisperCachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    WhisperAvatar(username: username, size: 26, ring: false)
                }
            }
        } else {
            WhisperAvatar(username: username, size: 26, ring: false)
        }
    }
}

/// One music note that rises, drifts, and fades on a loop.
private struct FloatingNote: View {
    let delay: Double
    let drift: CGSize
    @State private var go: Bool = false

    var body: some View {
        Image(systemName: "music.note")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 3)
            .offset(x: go ? drift.width : 0, y: go ? drift.height : 0)
            .scaleEffect(go ? 1.15 : 0.6)
            .opacity(go ? 0 : 0.95)
            .animation(.easeOut(duration: 1.9).repeatForever(autoreverses: false).delay(delay), value: go)
            .onAppear { go = true }
            .allowsHitTesting(false)
    }
}

// MARK: - Wave cover tile

/// A 9:16 cover for a wave in a sound-page grid — the still when the post
/// has one, else the video's first frame (generated once, cached).
struct WaveCoverThumb: View {
    let post: WhisperPost
    @State private var poster: UIImage?

    private var still: URL? {
        WhisperPostMeta.coverURL(from: post.caption)
            ?? post.mediaURLs.first(where: { !WhisperVideo.isVideo($0) })
    }
    private var video: URL? { post.mediaURLs.first(where: { WhisperVideo.isVideo($0) }) }

    var body: some View {
        Color(white: 0.1)
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .overlay {
                cover
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(compactCount(max(post.likes, 0)))
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .padding(6)
            }
            .clipped()
            .task(id: video) {
                poster = nil
                guard still == nil, let video else { return }
                let generation = AccountStorage.generation
                let image = await WhisperWavePosterCache.shared.poster(for: video)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                poster = image
            }
    }

    @ViewBuilder
    private var cover: some View {
        if let still {
            WhisperSizedAsyncImage(url: still) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    fallback
                }
            }
        } else if let poster {
            Image(uiImage: poster)
                .resizable()
                .scaledToFill()
        } else {
            fallback
        }
    }

    private var fallback: some View {
        LinearGradient(
            colors: [post.accent.opacity(0.9), post.accent.opacity(0.45)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func compactCount(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        case 1_000...: return String(format: "%.1fK", Double(n) / 1_000).replacingOccurrences(of: ".0K", with: "K")
        default: return "\(n)"
        }
    }
}

// MARK: - The sound page

/// TikTok's Sound Page: the sound's art, title and creator, how many waves
/// wear it, "Use this sound", Save, and the grid of every wave made with it.
struct WhisperSoundSheet: View {
    let sound: WhisperStoryMusic
    let pool: [WhisperPost]
    let onUse: (WhisperStoryMusic) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var saved = WhisperSavedSounds.shared
    @State private var player = WhisperStoryMusicPlayer.shared
    @State private var openWave: WhisperPost?
    @State private var sourcePoster: UIImage?

    private let brand = LinearGradient(
        colors: [
            Color(red: 0.61, green: 0.91, blue: 0.77),
            Color(red: 0.05, green: 0.62, blue: 0.46),
            Color(red: 0.35, green: 0.37, blue: 0.91)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private var waves: [WhisperPost] { WhisperWaveSound.waves(using: sound, in: pool) }
    private var isOriginal: Bool { WhisperWaveSound.isOriginal(sound) }
    private var sourcePost: WhisperPost? {
        guard let id = WhisperWaveSound.originalPostID(sound) else { return nil }
        return pool.first { $0.id.uuidString.lowercased() == id }
    }
    private var isPlaying: Bool { player.nowPlayingID == sound.id && player.isPlaying }
    private var canPreview: Bool { !sound.previewURL.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    actions
                    grid
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            if player.nowPlayingID == sound.id { player.stop() }
        }
        .task {
            guard isOriginal, sound.artworkURL == nil, sourcePoster == nil,
                  let video = URL(string: sound.previewURL) else { return }
            if let img = await WhisperStoryPoster.firstFrame(of: video, maxSize: CGSize(width: 360, height: 640)) {
                await MainActor.run { sourcePoster = img }
            }
        }
        .fullScreenCover(item: $openWave) { post in
            WhisperReelsPlayerView(reels: waves, start: post)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Button {
                guard canPreview else { return }
                Haptics.tap()
                player.toggle(sound)
            } label: {
                ZStack {
                    artwork
                        .frame(width: 100, height: 100)
                        .clipShape(.rect(cornerRadius: 18, style: .continuous))
                    if canPreview {
                        Circle()
                            .fill(.black.opacity(0.45))
                            .frame(width: 40, height: 40)
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canPreview)
            .accessibilityLabel(isPlaying ? "Pause preview" : "Play preview")

            VStack(alignment: .leading, spacing: 5) {
                Text(isOriginal ? "Original sound" : sound.title)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if isOriginal {
                        WhisperAvatar(username: sound.artist, size: 18, ring: false)
                    }
                    Text(isOriginal ? sound.artist : sound.artist)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Text(waves.count == 1 ? "1 wave" : "\(waves.count.formatted()) waves")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = sound.artworkURL, let url = URL(string: art) {
            WhisperCachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    artFallback
                }
            }
        } else if let sourcePoster {
            Image(uiImage: sourcePoster)
                .resizable()
                .scaledToFill()
        } else {
            artFallback
        }
    }

    private var artFallback: some View {
        ZStack {
            brand.opacity(0.9)
            if isOriginal {
                WhisperAvatar(username: sound.artist, size: 56, ring: false)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.success()
                onUse(sound)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Use this sound")
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(brand, in: Capsule())
                .shadow(color: Color(red: 0.05, green: 0.62, blue: 0.46).opacity(0.35), radius: 12, y: 4)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                saved.toggle(sound)
            } label: {
                let on = saved.isSaved(sound)
                HStack(spacing: 6) {
                    Image(systemName: on ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(on ? "Saved" : "Save")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.10), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(saved.isSaved(sound) ? "Remove from saved sounds" : "Save sound")
        }
    }

    // MARK: Grid

    private var grid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(waves.isEmpty ? "NO WAVES YET" : "WAVES WITH THIS SOUND")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.5))
            if waves.isEmpty {
                VStack(spacing: 8) {
                    WhisperMeetDoodle(symbol: "waveform", height: 120)
                        .environment(\.colorScheme, .dark)
                    Text("Be the first to make a wave with it.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    ForEach(waves) { post in
                        Button {
                            Haptics.tap()
                            openWave = post
                        } label: {
                            WaveCoverThumb(post: post)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Wave by \(post.username)")
                    }
                }
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
            }
        }
    }
}
