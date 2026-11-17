import Foundation
import Supabase
import SwiftUI

// MARK: - Article model

nonisolated struct WhisperArticle: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
    let excerpt: String
    let cover_url: String?
    let category: String?
    let author_name: String?
    let author_user_id: String?
    let paragraphs: [String]?
    let published: Bool
    let published_at: String?
    let created_at: String?
    let updated_at: String?
    /// Linked Whisper film — when set, the reader embeds a tappable film
    /// card (optionally seeking to `clip_time_seconds`).
    let film_id: String?
    let clip_time_seconds: Int?

    nonisolated enum CodingKeys: String, CodingKey {
        case id, slug, title, excerpt, cover_url, category, author_name
        case author_user_id, paragraphs, published, published_at, created_at, updated_at
        case film_id, clip_time_seconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        slug = (try? c.decodeIfPresent(String.self, forKey: .slug)) ?? ""
        title = try c.decode(String.self, forKey: .title)
        excerpt = (try? c.decodeIfPresent(String.self, forKey: .excerpt)) ?? ""
        cover_url = try? c.decodeIfPresent(String.self, forKey: .cover_url)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        author_name = try? c.decodeIfPresent(String.self, forKey: .author_name)
        author_user_id = try? c.decodeIfPresent(String.self, forKey: .author_user_id)
        paragraphs = try? c.decodeIfPresent([String].self, forKey: .paragraphs)
        published = (try? c.decodeIfPresent(Bool.self, forKey: .published)) ?? true
        published_at = try? c.decodeIfPresent(String.self, forKey: .published_at)
        created_at = try? c.decodeIfPresent(String.self, forKey: .created_at)
        updated_at = try? c.decodeIfPresent(String.self, forKey: .updated_at)
        film_id = try? c.decodeIfPresent(String.self, forKey: .film_id)
        clip_time_seconds = try? c.decodeIfPresent(Int.self, forKey: .clip_time_seconds)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(slug, forKey: .slug)
        try c.encode(title, forKey: .title)
        try c.encode(excerpt, forKey: .excerpt)
        try c.encodeIfPresent(cover_url, forKey: .cover_url)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(author_name, forKey: .author_name)
        try c.encodeIfPresent(author_user_id, forKey: .author_user_id)
        try c.encodeIfPresent(paragraphs, forKey: .paragraphs)
        try c.encode(published, forKey: .published)
        try c.encodeIfPresent(published_at, forKey: .published_at)
        try c.encodeIfPresent(created_at, forKey: .created_at)
        try c.encodeIfPresent(updated_at, forKey: .updated_at)
        try c.encodeIfPresent(film_id, forKey: .film_id)
        try c.encodeIfPresent(clip_time_seconds, forKey: .clip_time_seconds)
    }

    var formattedDate: String {
        guard let raw = published_at ?? created_at,
              let date = WhisperBackendService.parseISO(raw) else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Articles service

/// Fetches published articles from Supabase (anon read) and manages author
/// articles through the backend API. Mirrors the web app's articles.ts.
@MainActor
@Observable
final class WhisperArticlesService {
    static let shared = WhisperArticlesService()

    private let client = SupabaseService.shared.client
    private let billing = WhisperBillingService.shared

    var publishedArticles: [WhisperArticle] = []
    var myArticles: [WhisperArticle] = []
    var isLoading: Bool = false
    var lastError: String?

    private init() {}

    /// Fetches published articles from Supabase (public read).
    func fetchPublished() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [WhisperArticle] = try await client
                .from("whisper_articles")
                .select()
                .eq("published", value: true)
                .order("published_at", ascending: false)
                .limit(100)
                .execute()
                .value
            publishedArticles = rows
        } catch {
            // Table may not exist yet — return empty.
            lastError = error.localizedDescription
        }
    }

    /// Badge holder: fetch their own articles (drafts included) via the backend.
    func fetchMyArticles() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await billing.authorFetchArticles()
            myArticles = rows.compactMap { dict in
                guard let data = try? JSONSerialization.data(withJSONObject: dict),
                      let article = try? JSONDecoder().decode(WhisperArticle.self, from: data) else {
                    return nil
                }
                return article
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Badge holder: save (create or update) their own article.
    func saveArticle(
        id: String?,
        title: String,
        excerpt: String,
        coverURL: String,
        category: String,
        paragraphs: [String],
        published: Bool
    ) async throws -> String {
        var input: [String: Any] = [
            "title": title,
            "excerpt": excerpt,
            "cover_url": coverURL,
            "category": category,
            "paragraphs": paragraphs,
            "published": published,
        ]
        if let id { input["id"] = id }
        let resultID = try await billing.authorUpsertArticle(input)
        await fetchMyArticles()
        return resultID
    }

    /// Badge holder: delete their own article.
    func deleteArticle(id: String) async {
        do {
            try await billing.authorDeleteArticle(id: id)
            myArticles.removeAll { $0.id == id }
        } catch {
            lastError = error.localizedDescription
        }
    }
}

// MARK: - Article editor view (for badge holders)

/// Article editor for badge holders (coaches, athletes, verified creators).
/// Lets them write, edit, and publish articles that appear on the public
/// site and in the in-app articles feed. Mirrors the web's WriteArticles page.
struct WhisperArticleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let editingArticle: WhisperArticle?

    @State private var service = WhisperArticlesService.shared
    @State private var title: String = ""
    @State private var excerpt: String = ""
    @State private var coverURL: String = ""
    @State private var category: String = "Training"
    @State private var paragraphTexts: [String] = [""]
    @State private var isPublished: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var showSaved: Bool = false

    private let categories = ["Training", "Nutrition", "Recovery", "Mindset", "Community", "Coaching"]

    init(article: WhisperArticle? = nil) {
        self.editingArticle = article
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        titleField
                        excerptField
                        coverURLField
                        categoryPicker
                        paragraphsSection
                        publishToggle
                        saveButton
                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 20)
                        }
                        if showSaved {
                            Text("Article saved successfully!")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
                                .padding(.horizontal, 20)
                        }
                        Color.clear.frame(height: 32)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(editingArticle != nil ? "Edit Article" : "New Article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .onAppear { loadArticle() }
    }

    private func loadArticle() {
        guard let article = editingArticle else { return }
        title = article.title
        excerpt = article.excerpt
        coverURL = article.cover_url ?? ""
        category = article.category ?? "Training"
        paragraphTexts = article.paragraphs ?? [""]
        if paragraphTexts.isEmpty { paragraphTexts = [""] }
        isPublished = article.published
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TITLE")
                .font(.caption2.weight(.heavy))
                .tracking(1)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Your article title", text: $title)
                .font(.body.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(12)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
        .padding(.horizontal, 20)
    }

    private var excerptField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXCERPT")
                .font(.caption2.weight(.heavy))
                .tracking(1)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("A short summary (shown on the articles page)", text: $excerpt, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1...3)
                .padding(12)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
        .padding(.horizontal, 20)
    }

    private var coverURLField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COVER IMAGE URL")
                .font(.caption2.weight(.heavy))
                .tracking(1)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("https://...", text: $coverURL)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
        .padding(.horizontal, 20)
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CATEGORY")
                .font(.caption2.weight(.heavy))
                .tracking(1)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        Button {
                            Haptics.tap()
                            category = cat
                        } label: {
                            Text(cat)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(category == cat ? .white : WhisperTheme.ink(colorScheme))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    category == cat ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule().strokeBorder(
                                        WhisperTheme.hairline(colorScheme),
                                        lineWidth: category == cat ? 0 : 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var paragraphsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CONTENT")
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Spacer()
                Button {
                    Haptics.tap()
                    paragraphTexts.append("")
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add paragraph")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                .buttonStyle(.plain)
            }
            ForEach(paragraphTexts.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .frame(width: 20, alignment: .center)
                    VStack(spacing: 6) {
                        TextField("Write paragraph \(i + 1)...", text: Binding(
                            get: { paragraphTexts[i] },
                            set: { paragraphTexts[i] = $0 }
                        ), axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(3...10)
                        .padding(10)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                        if paragraphTexts.count > 1 {
                            Button {
                                Haptics.tap()
                                paragraphTexts.remove(at: i)
                            } label: {
                                Text("Remove")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var publishToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Publish immediately")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("If off, the article is saved as a draft.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Toggle("", isOn: $isPublished)
                .labelsHidden()
                .tint(WhisperTheme.ink(colorScheme))
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 20)
    }

    private var saveButton: some View {
        Button {
            Haptics.tap()
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().tint(.white)
                }
                Text(isPublished ? "Publish Article" : "Save Draft")
                    .font(.body.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(title.isEmpty ? WhisperTheme.muted(colorScheme) : WhisperTheme.ink(colorScheme), in: Capsule())
            .foregroundStyle(WhisperTheme.surface(colorScheme))
        }
        .buttonStyle(.plain)
        .disabled(title.isEmpty || isSaving)
        .padding(.horizontal, 20)
    }

    private func save() async {
        guard !title.isEmpty else {
            errorMessage = "Title is required."
            return
        }
        let cleanParagraphs = paragraphTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanParagraphs.isEmpty else {
            errorMessage = "Add at least one paragraph."
            return
        }
        isSaving = true
        errorMessage = nil
        showSaved = false
        defer { isSaving = false }
        do {
            _ = try await service.saveArticle(
                id: editingArticle?.id,
                title: title,
                excerpt: excerpt,
                coverURL: coverURL,
                category: category,
                paragraphs: cleanParagraphs,
                published: isPublished
            )
            showSaved = true
            // Dismiss after a brief delay so the user sees the confirmation.
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - My articles list

/// Shows the badge holder's own articles with edit/delete actions.
struct WhisperMyArticlesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var service = WhisperArticlesService.shared
    @State private var editingArticle: WhisperArticle?
    @State private var showEditor: Bool = false
    @State private var newArticle: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        newArticleButton
                        if service.isLoading && service.myArticles.isEmpty {
                            ProgressView()
                                .tint(WhisperTheme.ink(colorScheme))
                                .padding(.top, 40)
                        } else if service.myArticles.isEmpty {
                            emptyState
                        } else {
                            ForEach(service.myArticles) { article in
                                articleRow(article)
                            }
                        }
                        if let err = service.lastError {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 20)
                        }
                        Color.clear.frame(height: 32)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("My Articles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .sheet(isPresented: $showEditor) {
                WhisperArticleEditorView(article: newArticle ? nil : editingArticle)
            }
        }
        .task { await service.fetchMyArticles() }
    }

    private var newArticleButton: some View {
        Button {
            Haptics.tap()
            newArticle = true
            editingArticle = nil
            showEditor = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                Text("Write New Article")
                    .font(.body.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(WhisperTheme.ink(colorScheme), in: Capsule())
            .foregroundStyle(WhisperTheme.surface(colorScheme))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: "doc.text", height: 144)
            Text("No articles yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Share your expertise — write training tips, nutrition guides, or coaching insights.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 24)
        }
        .padding(.top, 40)
    }

    private func articleRow(_ article: WhisperArticle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(article.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(article.category ?? "Training")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WhisperTheme.ink(colorScheme), in: Capsule())
                        if !article.published {
                            Text("DRAFT")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color(red: 0.92, green: 0.63, blue: 0.18))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.92, green: 0.63, blue: 0.18).opacity(0.15), in: Capsule())
                        }
                        if !article.formattedDate.isEmpty {
                            Text(article.formattedDate)
                                .font(.caption2)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }
                }
                Spacer()
            }
            if !article.excerpt.isEmpty {
                Text(article.excerpt)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    newArticle = false
                    editingArticle = article
                    showEditor = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    Haptics.warning()
                    Task {
                        await service.deleteArticle(id: article.id)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }
}
