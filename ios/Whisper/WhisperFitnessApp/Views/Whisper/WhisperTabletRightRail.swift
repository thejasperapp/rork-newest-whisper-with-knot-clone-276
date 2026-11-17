import SwiftUI

struct WhisperTabletRightRail: View {
    @Environment(\.colorScheme) private var scheme
    @State private var query: String = ""
    @State private var results: [WhisperUserRow] = []
    @State private var suggestions: [WhisperUserRow] = []
    @State private var searching: Bool = false
    @State private var error: String? = nil
    @State private var selectedUser: WhisperUserRow? = nil
    @State private var backend = WhisperBackendService.shared
    @State private var articles = WhisperArticlesService.shared
    @State private var article: WhisperArticle? = nil
    let searchAll: () -> Void
    let openLive: () -> Void
    let openCommunity: (WhisperCommunity) -> Void

    private var trending: [WhisperCommunity] {
        let counts = Dictionary(grouping: backend.posts.compactMap(\.community_id), by: { $0 }).mapValues(\.count)
        return Array(WhisperCommunity.catalog.filter { (counts[$0.id] ?? 0) > 0 }.sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }.prefix(6))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                card {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search Whisper", text: $query).font(.subheadline).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }.padding(12).background(WhisperTheme.card(scheme), in: Capsule())
                    if searching { ProgressView("Searching…").font(.caption) }
                    if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    ForEach(results.prefix(6)) { user in person(user) }
                    Button("See all results", action: searchAll).font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                if !trending.isEmpty {
                    card {
                        Label("Trending", systemImage: "chart.line.uptrend.xyaxis").font(.subheadline.weight(.bold))
                        ForEach(trending) { item in
                            Button { openCommunity(item) } label: {
                                HStack { Text(item.name).font(.subheadline); Spacer(); Image(systemName: "chevron.right").font(.caption2) }.frame(minHeight: 40)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !articles.publishedArticles.isEmpty {
                    card {
                        Label("Latest articles", systemImage: "book").font(.subheadline.weight(.bold))
                        ForEach(articles.publishedArticles.prefix(3)) { item in
                            Button { article = item } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(item.author_name ?? "Whisper").font(.caption2).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                card {
                    Button(action: openLive) { Label("Live on Whisper", systemImage: "dot.radiowaves.left.and.right").font(.subheadline.weight(.bold)).frame(minHeight: 44) }.buttonStyle(.plain)
                }
                card {
                    Label("Who to follow", systemImage: "person.2").font(.subheadline.weight(.bold))
                    ForEach(suggestions.prefix(5)) { user in person(user) }
                    if suggestions.isEmpty { Text("Discover people and start a conversation.").font(.caption).foregroundStyle(.secondary) }
                }
                Text("Whisper · 2026").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 2)
            }
            .padding(.vertical, 24).padding(.leading, 24).padding(.trailing, 4)
        }.scrollIndicators(.hidden).frame(width: 320)
            .foregroundStyle(WhisperTheme.ink(scheme))
            .task {
                let epoch = AccountStorage.generation
                let rows = await WhisperUserService.shared.suggestions(limit: 5)
                guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                suggestions = rows
            }
            .task(id: query) {
                results = []; error = nil
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { searching = false; return }
                let epoch = AccountStorage.generation
                searching = true
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    let rows = try await WhisperUserService.shared.mentionSuggestions(query, matchingNames: true)
                    guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                    results = rows; searching = false
                    if rows.isEmpty { error = "No matching people." }
                } catch {
                    guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                    searching = false; self.error = "Couldn't search. Try again."
                }
            }
            .task { if articles.publishedArticles.isEmpty { await articles.fetchPublished() } }
            .sheet(item: $article) { item in NavigationStack { WhisperArticleReaderView(article: item) } }
            .sheet(item: $selectedUser) { user in NavigationStack { WhisperUserProfileView(user: user) } }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content).frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(WhisperTheme.surface(scheme), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WhisperTheme.hairline(scheme), lineWidth: 0.6))
    }
    private func person(_ user: WhisperUserRow) -> some View {
        Button { selectedUser = user } label: {
            HStack(spacing: 10) {
                WhisperAvatar(username: user.username, size: 36, imageURL: user.profile_image_url.flatMap(URL.init(string:)), ring: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.display_name ?? user.username).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("@\(user.username)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.frame(minHeight: 48)
        }.buttonStyle(.plain)
    }
}
