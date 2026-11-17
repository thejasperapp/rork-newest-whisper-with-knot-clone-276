import Foundation
import Observation

@MainActor @Observable final class WhisperPostActivityViewModel {
    private(set) var post: WhisperPost?
    private(set) var items: [WhisperPostActivityItem] = []
    private(set) var likes: Int?
    private(set) var loading: Bool = true
    private(set) var error: String?
    private(set) var likesError: Bool = false
    private(set) var quotesError: Bool = false
    private(set) var moreLikes: Bool = true
    private(set) var moreQuotes: Bool = true
    private(set) var loadedQuotes: Bool = false
    private var likeOffset: Int = 0
    private var quoteOffset: Int = 0
    private var requestID: UUID = UUID()
    private var closed: Bool = false
    private let generation: UUID = AccountStorage.generation
    var isOwner: Bool { post?.authorUserID?.lowercased() == AccountStorage.currentUserID.lowercased() }
    var quoteCountLabel: String {
        guard loadedQuotes else { return "—" }
        let count = items.filter(\.isQuote).count
        return moreQuotes ? (count == 0 ? "—" : "\(count)+") : count.formatted()
    }
    func invalidate() { requestID = UUID(); post = nil; items = []; likes = nil; loading = true }
    func close() { closed = true; invalidate() }
    private func valid(_ request: UUID) -> Bool { !closed && request == requestID && generation == AccountStorage.generation && !Task.isCancelled }
    func load(postID: String) async {
        guard !closed, generation == AccountStorage.generation, !Task.isCancelled else { return }
        let request = UUID(); requestID = request
        post = nil; items = []; likes = nil; error = nil; loading = true
        likeOffset = 0; quoteOffset = 0; moreLikes = true; moreQuotes = true; loadedQuotes = false
        likesError = false; quotesError = false
        do {
            let original = try await WhisperPostActivityService.original(postID)
            guard valid(request) else { return }
            guard let original else { error = "This post is no longer available to you."; loading = false; return }
            post = original
            if isOwner {
                let snapshot = await WhisperPostInsightsService.shared.snapshot(for: postID)
                guard valid(request) else { return }; likes = snapshot.likes
            }
            await page(postID: postID, quotes: false, request: request)
            guard valid(request), post != nil else { return }
            await page(postID: postID, quotes: true, request: request)
            guard valid(request) else { return }; loading = false
        } catch {
            guard valid(request) else { return }
            self.error = "Couldn't load post activity. Please try again."
            loading = false
        }
    }
    func more(postID: String, quotes: Bool) async {
        guard !loading, !closed else { return }
        let request = requestID; loading = true
        await page(postID: postID, quotes: quotes, request: request)
        if valid(request) { loading = false }
    }
    private func page(postID: String, quotes: Bool, request: UUID) async {
        if quotes { quotesError = false } else { likesError = false }
        do {
            let next = quotes ? try await WhisperPostActivityService.quotes(postID, offset: quoteOffset) : try await WhisperPostActivityService.likes(postID, offset: likeOffset)
            guard valid(request) else { return }
            var seen = Set(items.map(\.id))
            items.append(contentsOf: next.items.filter { seen.insert($0.id).inserted })
            items.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            if quotes { quoteOffset += next.consumed; moreQuotes = next.hasMore; loadedQuotes = true }
            else { likeOffset += next.consumed; moreLikes = next.hasMore }
        } catch {
            guard valid(request) else { return }
            if (error as? URLError)?.code == .noPermissionsToReadFile {
                invalidate()
                self.error = "This post is no longer available to you."
                loading = false
            } else if quotes {
                quotesError = true
            } else {
                likesError = true
            }
        }
    }
}
