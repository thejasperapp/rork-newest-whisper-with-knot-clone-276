import SwiftUI

/// Simulated feed backdrop for the auth screen — mirrors the web's
/// `Auth.tsx` simulated posts: realistic fake usernames, profile pictures
/// from pravatar.cc, image posts from picsum.photos, gentle auto-scrolling
/// columns, and auto-liking heart bursts. No real user content is shown.
///
/// iOS uses 2 columns (vs web's 3) to fit the narrower screen. The same
/// 12 posts, avatars, images, likes, and captions are used on both platforms.

// MARK: - Data

private struct SimPost: Identifiable {
    let id: String
    let username: String
    let displayName: String
    let verified: Bool
    let avatarURL: String
    let caption: String
    let imageURL: String?
    let likes: Int
    let comments: Int
    let time: String
}

/// The exact same 12 posts used on the web (Auth.tsx SIM_POSTS).
/// Avatars: pravatar.cc, images: picsum.photos — identical on both platforms.
private let simPosts: [SimPost] = [
    .init(id: "s1", username: "maya.runs", displayName: "Maya Chen", verified: true,
          avatarURL: "https://i.pravatar.cc/96?img=47",
          caption: "morning runs hit different when the city is still asleep",
          imageURL: "https://picsum.photos/seed/whisper-run/640/480",
          likes: 142, comments: 8, time: "2h"),
    .init(id: "s2", username: "devon.films", displayName: "Devon Park", verified: true,
          avatarURL: "https://i.pravatar.cc/96?img=12",
          caption: "just wrapped my first short film. can't believe this is real",
          imageURL: nil,
          likes: 389, comments: 24, time: "4h"),
    .init(id: "s3", username: "aria_lifts", displayName: "Aria Torres", verified: false,
          avatarURL: "https://i.pravatar.cc/96?img=32",
          caption: "training day 47. the grind doesn't stop",
          imageURL: "https://picsum.photos/seed/whisper-gym/640/480",
          likes: 67, comments: 3, time: "5h"),
    .init(id: "s4", username: "coach.eli", displayName: "Eli Brooks", verified: true,
          avatarURL: "https://i.pravatar.cc/96?img=56",
          caption: "three of my athletes hit PRs this week. proud coach moment",
          imageURL: nil,
          likes: 218, comments: 19, time: "6h"),
    .init(id: "s5", username: "nina.creates", displayName: "Nina Okafor", verified: false,
          avatarURL: "https://i.pravatar.cc/96?img=5",
          caption: "golden hour never misses",
          imageURL: "https://picsum.photos/seed/whisper-golden/640/480",
          likes: 501, comments: 32, time: "8h"),
    .init(id: "s6", username: "jax_hoops", displayName: "Jax Rivera", verified: false,
          avatarURL: "https://i.pravatar.cc/96?img=68",
          caption: "5am shootaround. nobody watching, everybody wondering",
          imageURL: "https://picsum.photos/seed/whisper-court/640/480",
          likes: 93, comments: 6, time: "9h"),
    .init(id: "s7", username: "sofia.eats", displayName: "Sofia Marino", verified: false,
          avatarURL: "https://i.pravatar.cc/96?img=25",
          caption: "meal prep sunday - 12 meals, 2 hours, zero excuses",
          imageURL: "https://picsum.photos/seed/whisper-meal/640/480",
          likes: 156, comments: 11, time: "11h"),
    .init(id: "s8", username: "theo.writes", displayName: "Theo Nakamura", verified: true,
          avatarURL: "https://i.pravatar.cc/96?img=15",
          caption: "new article drops friday. this one's personal.",
          imageURL: nil,
          likes: 274, comments: 41, time: "12h"),
    .init(id: "s9", username: "lena.tracks", displayName: "Lena Hoffmann", verified: false,
          avatarURL: "https://i.pravatar.cc/96?img=44",
          caption: "first sub-20 5k!! two years in the making",
          imageURL: "https://picsum.photos/seed/whisper-track/640/480",
          likes: 448, comments: 57, time: "14h"),
    .init(id: "s10", username: "marcus.talks", displayName: "Marcus Reid", verified: true,
          avatarURL: "https://i.pravatar.cc/96?img=60",
          caption: "went live with 3 friends last night - group lives are a game changer",
          imageURL: nil,
          likes: 312, comments: 28, time: "16h"),
    .init(id: "s11", username: "ivy.climbs", displayName: "Ivy Laurent", verified: false,
          avatarURL: "https://i.pravatar.cc/96?img=36",
          caption: "finally sent the V7 I've been projecting all month",
          imageURL: "https://picsum.photos/seed/whisper-climb/640/480",
          likes: 187, comments: 14, time: "18h"),
    .init(id: "s12", username: "omar.codes", displayName: "Omar Haddad", verified: false,
          avatarURL: "https://i.pravatar.cc/96?img=53",
          caption: "shipped the app. now we run it back tomorrow.",
          imageURL: nil,
          likes: 84, comments: 9, time: "20h"),
]

// MARK: - Backdrop

struct WhisperSimulatedFeedBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Two columns of posts scrolling at different speeds — iOS fits 2
    /// columns comfortably on a phone screen (web uses 3).
    private var columns: [[SimPost]] {
        [Array(simPosts.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element }),
         Array(simPosts.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element })]
    }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme)

            HStack(spacing: 10) {
                ForEach(Array(columns.enumerated()), id: \.offset) { colIdx, col in
                    SimFeedColumn(posts: col, scrollDuration: [52, 66][colIdx])
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .opacity(0.82)

            // Soft veil so the floating auth card always stays readable.
            LinearGradient(
                colors: [
                    WhisperTheme.surface(colorScheme).opacity(0.65),
                    WhisperTheme.surface(colorScheme).opacity(0.32),
                    WhisperTheme.surface(colorScheme).opacity(0.72),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - Scrolling column

/// Infinite-scrolling column — the iOS equivalent of the web's CSS
/// `translateY(-50%)` keyframe loop.
///
/// Deliberately driven by `TimelineView` clock math instead of a
/// `withAnimation(.repeatForever)` state animation: repeatForever ambient
/// animations leak into every child state change (AsyncImage phase loads,
/// the auto-like hearts), which broke the card layout into floating
/// fragments. Pure time-based offset = zero animation interference.
private struct SimFeedColumn: View {
    let posts: [SimPost]
    /// Seconds for one full loop of the column content.
    let scrollDuration: Double

    @State private var contentHeight: CGFloat = 0
    /// Fixed at first render so the loop phase is stable across re-renders.
    @State private var startDate: Date = Date()

    var body: some View {
        let doubled = posts + posts
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let half = contentHeight / 2
                let elapsed = context.date.timeIntervalSince(startDate)
                let speed = half > 0 ? Double(half) / scrollDuration : 0
                let offset: CGFloat = half > 0
                    ? -CGFloat((elapsed * speed).truncatingRemainder(dividingBy: Double(half)))
                    : 0

                VStack(spacing: 10) {
                    ForEach(Array(doubled.enumerated()), id: \.offset) { idx, post in
                        SimPostCard(post: post, likeDelay: 1.2 + Double((idx * 17) % 90) / 10.0)
                            .frame(width: geo.size.width)
                    }
                }
                .padding(.vertical, 8)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { contentHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, h in contentHeight = h }
                    }
                )
                .offset(y: offset)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
            .mask(LinearGradient(
                colors: [.clear, .white.opacity(0.35), .white, .white, .white.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
        .clipped()
    }
}

// MARK: - Simulated post card

private struct SimPostCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let post: SimPost
    let likeDelay: Double

    @State private var liked: Bool = false
    @State private var heartBurst: Bool = false

    private var likeCount: Int {
        post.likes + (liked ? 1 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header — simulated profile picture + handle
            HStack(spacing: 8) {
                SimAvatar(url: post.avatarURL, size: 32)
                    .layoutPriority(1)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(post.username)
                            .font(.system(size: 12, weight: .bold))
                        if post.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(red: 0.055, green: 0.647, blue: 0.914))
                        }
                    }
                    Text("\(post.time) ago")
                        .font(.system(size: 10))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 10))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }

            // Image post — real photos from picsum.photos matching web
            if let imageURL = post.imageURL {
                SimPostImage(url: imageURL)
                    .frame(height: 120)
                    .clipShape(.rect(cornerRadius: 14))
            }

            Text(WhisperPostMeta.strip(from: post.caption))
                .font(.system(size: 12))
                .lineLimit(3)
                .foregroundStyle(WhisperTheme.ink(colorScheme))

            // Engagement bar — likes match actual post data + auto-like
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 13))
                        .foregroundStyle(liked ? .red : WhisperTheme.ink(colorScheme).opacity(0.55))
                        .scaleEffect(liked ? 1.1 : 1.0)
                    Text("\(likeCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 13))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                    Text("\(post.comments)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
                Image(systemName: "bookmark")
                    .font(.system(size: 13))
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                Image(systemName: "paperplane")
                    .font(.system(size: 13))
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
            }
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
        .overlay {
            if heartBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)
                    .shadow(color: .red.opacity(0.4), radius: 8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .task { await autoLike() }
    }

    /// Instagram-style double-tap like: heart fills red with a spring pop
    /// and a big heart bursts over the post, then fades — the same real
    /// like animation the feed uses, and the same behaviour as the web
    /// backdrop's auto-like.
    private func autoLike() async {
        try? await Task.sleep(for: .seconds(likeDelay))
        guard !liked else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            liked = true
            heartBurst = true
        }
        try? await Task.sleep(for: .seconds(0.9))
        withAnimation(.easeOut(duration: 0.3)) {
            heartBurst = false
        }
    }
}

// MARK: - Avatar (pravatar.cc)

/// Loads a profile picture from pravatar.cc — same URLs as the web.
private struct SimAvatar: View {
    let url: String
    let size: CGFloat

    var body: some View {
        WhisperCachedAsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure, .empty:
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(.white.opacity(0.6))
                    }
            @unknown default:
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Post image (picsum.photos)

/// Loads a post image from picsum.photos — same URLs as the web.
private struct SimPostImage: View {
    let url: String

    var body: some View {
        Color(.secondarySystemBackground)
            .frame(maxWidth: .infinity)
            .overlay {
                WhisperCachedAsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    case .failure, .empty:
                        Color.gray.opacity(0.2)
                            .overlay {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                    @unknown default:
                        Color.gray.opacity(0.2)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 14))
    }
}
