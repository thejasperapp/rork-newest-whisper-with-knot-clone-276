import SwiftUI
import Supabase

/// Fresh, server-counted engagement. Nil means unavailable, never an inferred zero.
struct WhisperPostInsightsSnapshot: Equatable {
    var likes: Int?
    var comments: Int?
    var views: Int?

    /// Engagement rate = (likes + comments) / max(views, 1).
    /// Returns 0 when there are no views yet.
    var engagementRate: Double {
        guard let views, let likes, let comments, views > 0 else { return 0 }
        return Double(likes + comments) / Double(views)
    }
}

/// Records account-scoped impressions and loads each metric independently.
@MainActor
final class WhisperPostInsightsService {
    static let shared = WhisperPostInsightsService()
    private init() {}

    private var client: SupabaseClient { SupabaseService.shared.client }
    private var recordedThisSession: Set<String> = []
    private var pendingViews: Set<String> = []
    private var tableDisabled: Bool = false

    /// Inserts a view row for the given post (idempotent per session per
    /// post). Safe to call from feed cards as they scroll into view —
    /// failures are swallowed and the table is marked disabled after the
    /// first missing-relation error so we don't keep hitting Supabase.
    func trackView(postID: String, authorUserID: String?) async {
        guard !tableDisabled else { return }
        let viewerUID = AccountStorage.currentUserID
        let epoch = AccountStorage.generation
        guard UUID(uuidString: viewerUID) != nil else { return }
        let key = viewerUID.lowercased() + ":" + postID.lowercased()
        guard !recordedThisSession.contains(key), pendingViews.insert(key).inserted else { return }
        defer { pendingViews.remove(key) }
        // Never count a post author viewing their own post.
        if let authorUserID, authorUserID.lowercased() == viewerUID.lowercased() {
            return
        }
        struct Row: Codable { let post_id: String; let viewer_user_id: String }
        do {
            try WhisperChatMediaService.checkAccount(viewerUID, generation: epoch)
            try await client
                .from("whisper_post_views")
                .insert(Row(post_id: postID, viewer_user_id: viewerUID))
                .execute()
            try WhisperChatMediaService.checkAccount(viewerUID, generation: epoch)
            recordedThisSession.insert(key)
        } catch {
            guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
            let msg = error.localizedDescription.lowercased()
            if msg.contains("relation") && msg.contains("does not exist") {
                tableDisabled = true
            }
            // Duplicates / RLS denials are fine — just ignore.
        }
    }

    /// Exact HEAD counts avoid cached totals and server row-limit truncation.
    func snapshot(for postID: String) async -> WhisperPostInsightsSnapshot {
        async let likes = count(table: "whisper_post_likes", postID: postID)
        async let comments = count(table: "whisper_post_comments", postID: postID)
        async let views = count(table: "whisper_post_views", postID: postID)
        return await WhisperPostInsightsSnapshot(likes: likes, comments: comments, views: views)
    }

    private func count(table: String, postID: String) async -> Int? {
        let account = AccountStorage.currentUserID; let epoch = AccountStorage.generation
        do {
            try WhisperChatMediaService.checkAccount(account, generation: epoch)
            let response = try await client.from(table).select("post_id", head: true, count: .exact)
                .eq("post_id", value: postID).execute()
            try WhisperChatMediaService.checkAccount(account, generation: epoch)
            return response.count
        } catch { return nil }
    }
}

/// Bottom-sheet style insights view shown when a post author taps the
/// "View insights" menu item. Pulls counters via
/// `WhisperPostInsightsService` and renders a Threads-style stat board
/// with the four core metrics plus an engagement-rate readout.
struct WhisperPostInsightsSheet: View {
    let post: WhisperPost
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var snapshot: WhisperPostInsightsSnapshot?
    @State private var loading: Bool = true
    @State private var retry: Int = 0
    @State private var showLikes: Bool = false

    private var postIDString: String { post.id.uuidString.lowercased() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    statGrid
                    Button { showLikes = true } label: {
                        Label("See who liked this post", systemImage: "heart").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.plain)
                    if !loading, snapshot?.likes == nil || snapshot?.comments == nil || snapshot?.views == nil {
                        Text("A dash means this metric couldn't be loaded. Counts are never estimated.")
                            .font(.footnote).foregroundStyle(WhisperTheme.muted(colorScheme))
                        Button("Refresh insights") { retry += 1 }.frame(minHeight: 44)
                    }
                    if snapshot?.views != nil { engagementRow }
                    captionPreview
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(WhisperTheme.surface(colorScheme))
            .navigationTitle("Post insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .whisperSheetBorder()
        .presentationContentInteraction(.scrolls)
        .sheet(isPresented: $showLikes) { WhisperPostLikesSheet(postID: postIDString) }
        .task(id: retry) {
            let epoch = AccountStorage.generation
            loading = true
            let result = await WhisperPostInsightsService.shared.snapshot(for: postIDString)
            guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
            snapshot = result; loading = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in snapshot = nil; showLikes = false; dismiss() }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("@\(post.username)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Text("Posted \(post.timeAgo) ago")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var statGrid: some View {
        HStack(spacing: 12) {
            statTile(value: snapshot?.views, label: "Views", systemImage: "eye.fill")
            statTile(value: snapshot?.likes, label: "Likes", systemImage: "heart.fill")
            statTile(value: snapshot?.comments, label: "Comments", systemImage: "bubble.left.fill")
        }
    }

    private func statTile(value: Int?, label: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
            if loading {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 36, alignment: .leading)
            } else {
                Text(value.map(formatted) ?? "—")
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(height: 36, alignment: .leading)
            }
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
    }

    private var engagementRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Engagement rate")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Text(engagementText)
                    .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            Spacer(minLength: 0)
            // Tiny progress bar — clamps the engagement rate into 0…0.25
            // so a healthy post sits around two-thirds full.
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(WhisperTheme.hairline(colorScheme))
                    .frame(width: 110, height: 8)
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color.orange, Color(red: 1.0, green: 0.5, blue: 0.2)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: max(8, min(110, 110 * (snapshot?.engagementRate ?? 0) / 0.25)), height: 8)
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
    }

    private var engagementText: String {
        guard let s = snapshot, s.likes != nil, s.comments != nil, s.views != nil else { return "—" }
        let pct = s.engagementRate * 100
        if pct < 0.05 { return "0%" }
        return String(format: pct >= 10 ? "%.0f%%" : "%.1f%%", pct)
    }

    private var captionPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Post")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Text(post.displayCaption.isEmpty ? "(media post)" : post.displayCaption)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(6)
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
    }

    private func formatted(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
