import SwiftUI

/// Shared owner/visitor activity destination. Original content is never shown before admission.
struct WhisperPostActivityView: View {
    let postID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: WhisperPostActivityViewModel = WhisperPostActivityViewModel()
    @State private var path: [Filter] = []
    @State private var openUser: WhisperUserRow?
    @State private var quote: QuoteRoute?
    @State private var retry: Int = 0
    @State private var showInsights: Bool = false
    @State private var blocks = WhisperBlockService.shared
    private enum Filter: String, Hashable { case likes = "Likes", quotes = "Quotes" }
    private struct QuoteRoute: Identifiable { let id: String }

    var body: some View {
        NavigationStack(path: $path) {
            content(filter: nil)
                .navigationTitle("Post activity").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { model.close(); dismiss() } label: { Image(systemName: "chevron.left").font(.title3).frame(width: 44, height: 44) }.accessibilityLabel("Back")
                    }
                }
                .navigationDestination(for: Filter.self) { filter in
                    content(filter: filter).navigationTitle(filter.rawValue).navigationBarTitleDisplayMode(.inline)
                }
                .navigationDestination(item: $openUser) { user in WhisperUserProfileView(user: user) }
                .whisperEdgeBack(isEnabled: path.isEmpty && openUser == nil) { model.close(); dismiss() }
        }.tint(WhisperTheme.ink(scheme))
            .task(id: retry) {
                guard scenePhase == .active else { return }
                async let following: Void = WhisperFollowService.shared.refreshIfStale()
                async let requests: Void = WhisperFollowRequestService.shared.refresh()
                await model.load(postID: postID)
                _ = await (following, requests)
            }
            .onChange(of: blocks.blockedUserIDs) { _, _ in model.invalidate(); retry += 1 }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in model.invalidate() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { retry += 1 } else { model.invalidate() }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in model.close(); quote = nil; openUser = nil; dismiss() }
            .sheet(isPresented: $showInsights) { if let post = model.post, model.isOwner { WhisperPostInsightsSheet(post: post) } }
            .fullScreenCover(item: $quote) { route in WhisperReferencedPostView(postID: route.id) }
    }
    private func content(filter: Filter?) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let post = model.post {
                    Button { quote = QuoteRoute(id: postID) } label: {
                        originalCard(post)
                    }.buttonStyle(.plain).accessibilityHint("Opens the original post")
                        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 12)
                    if filter == nil, model.isOwner {
                        Button { showInsights = true } label: { Label("View insights", systemImage: "chart.bar").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 20) }.buttonStyle(.plain)
                        summary("Likes", symbol: "heart", count: model.likes.map { $0.formatted() } ?? "—", filter: .likes)
                        summary("Quotes", symbol: "quote.bubble", count: model.quoteCountLabel, filter: .quotes)
                    }
                    let visible = model.items.filter { filter == nil || ($0.isQuote ? filter == .quotes : filter == .likes) }
                    ForEach(visible) { item in
                        WhisperPostActivityRow(item: item, onProfile: { openUser = item.profile }, onQuote: { if let id = item.quotePostID { quote = QuoteRoute(id: id) } })
                        Rectangle().fill(WhisperTheme.hairline(scheme)).frame(height: 0.5).padding(.leading, 62)
                    }
                    if visible.isEmpty && !model.loading && !model.likesError && !model.quotesError {
                        Text("No \(filter?.rawValue.lowercased() ?? "activity") to show yet.").font(.subheadline).foregroundStyle(.secondary).padding(32)
                    }
                    if model.loading { ProgressView().padding(24) }
                    if filter != .quotes && (model.moreLikes || model.likesError) {
                        Button(model.likesError ? "Couldn't load likes · Retry" : "Load more likes") { Task { await model.more(postID: postID, quotes: false) } }.frame(minHeight: 48).disabled(model.loading)
                    }
                    if filter != .likes && (model.moreQuotes || model.quotesError) {
                        Button(model.quotesError ? "Couldn't load quotes · Retry" : "Load more quotes") { Task { await model.more(postID: postID, quotes: true) } }.frame(minHeight: 48).disabled(model.loading)
                    }
                    if filter == .quotes {
                        Text("Only quotes you can access are shown. A + means more posts remain to be checked.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(20)
                    }
                } else if model.loading { ProgressView("Loading activity…").padding(40) }
                else {
                    Text(model.error ?? "Post unavailable").multilineTextAlignment(.center).padding(24)
                    Button("Try again") { retry += 1 }.frame(minHeight: 44)
                }
            }.padding(.bottom, 28)
        }.background(WhisperTheme.surface(scheme)).refreshable {
            guard scenePhase == .active else { return }
            await model.load(postID: postID)
        }
    }
    private func originalCard(_ post: WhisperPost) -> some View {
        let caption = WhisperContentPreview.text(post.caption, fallback: "Post", limit: 640)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                WhisperAvatar(username: post.username, size: 18, ring: false)
                Text(post.username).font(.subheadline.weight(.semibold)).lineLimit(1).layoutPriority(1)
                if WhisperVerifiedPerks.isVerified(username: post.username) { Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).font(.system(size: 11)) }
                if let community = post.communityName {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    Text(community).font(.subheadline.weight(.semibold)).foregroundStyle(.blue).lineLimit(1)
                }
                Text(post.timeAgo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            if !caption.isEmpty { Text(caption).font(.body).lineLimit(8).frame(maxWidth: .infinity, alignment: .leading) }
            if !post.mediaURLs.isEmpty { Label("\(post.mediaURLs.count) \(post.mediaURLs.count == 1 ? "attachment" : "attachments")", systemImage: "photo.on.rectangle").font(.caption).foregroundStyle(.secondary) }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(WhisperTheme.hairline(scheme), lineWidth: 1) }
    }
    private func summary(_ title: String, symbol: String, count: String, filter: Filter) -> some View {
        NavigationLink(value: filter) {
            HStack(spacing: 18) {
                Image(systemName: symbol).font(.system(size: 26, weight: .regular)).frame(width: 28)
                Text(title).font(.body.weight(.semibold))
                Spacer()
                Text(count).font(.body)
                Image(systemName: "chevron.right").font(.body)
            }.foregroundStyle(.primary).frame(minHeight: 54).padding(.horizontal, 20)
        }.buttonStyle(.plain)
            .overlay(alignment: .bottom) { Rectangle().fill(WhisperTheme.hairline(scheme)).frame(height: 0.5).padding(.leading, 62) }
    }
}
