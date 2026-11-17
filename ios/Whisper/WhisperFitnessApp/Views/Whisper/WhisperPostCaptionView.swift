import SwiftUI

/// The same readable caption and embedded cards in feed and post detail.
struct WhisperPostCaptionView: View {
    let text: String
    var font: Font = .subheadline
    var showsText: Bool = true
    var quoteDepth: Int = 0
    var parentPostID: UUID? = nil

    var body: some View {
        let parsed = WhisperContentEmbedParser.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            if showsText, !parsed.cleaned.isEmpty {
                WhisperMentionText(text: parsed.cleaned, font: font)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let quote = parsed.quote {
                WhisperQuotedPostCard(payload: quote, depth: quoteDepth, parentPostID: parentPostID)
                    .id(quote.postID.lowercased())
            }
            if let film = parsed.film { WhisperFilmEmbedInlineCard(payload: film) }
            if let article = parsed.article { WhisperArticleEmbedInlineCard(payload: article) }
        }
    }
}
