import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import CoreLocation
import Combine
import WebKit

// MARK: - Composer picker enum

/// Which picker the caller wants auto-presented when the full reply
/// composer mounts. Lets the detail-view pill hand off cleanly when the
/// user taps the photo / GIF / sticker icon on the minimal bar.
enum WhisperReplyComposerPicker {
    case photos, gif, sticker, camera, poll, voice
}

// MARK: - Attachments state

/// Bag of in-progress attachments hanging off a reply composer. All fields
/// optional / empty by default — they accumulate as the user taps icons in
/// the composer toolbar. `serialize(into:)` turns them into final body text
/// and uploaded URLs at send-time.
@MainActor
@Observable
final class WhisperComposerAttachments {
    var images: [UIImage] = []
    var gifURL: URL?
    var stickerURL: URL?
    var poll: WhisperPollDraft?
    var location: String?
    var voiceMemo: WhisperVoiceMemoAttachment?

    private var lastSubmissionFingerprint: Int?
    private var submissionID: String = UUID().uuidString.lowercased()

    /// An unchanged retry reuses its insert identity; editing the reply starts a new submission.
    func commentID(baseBody: String, postID: String, parentID: String?) -> String {
        var hasher = Hasher()
        hasher.combine(AccountStorage.generation); hasher.combine(postID.lowercased()); hasher.combine(parentID)
        hasher.combine(baseBody); images.forEach { hasher.combine(ObjectIdentifier($0)) }
        hasher.combine(gifURL); hasher.combine(stickerURL); hasher.combine(location)
        hasher.combine(poll?.question); hasher.combine(poll?.options); hasher.combine(voiceMemo?.data)
        let fingerprint = hasher.finalize()
        if let previous = lastSubmissionFingerprint, previous != fingerprint { submissionID = UUID().uuidString.lowercased() }
        lastSubmissionFingerprint = fingerprint
        return submissionID
    }

    var isEmpty: Bool {
        images.isEmpty && gifURL == nil && stickerURL == nil && poll == nil && location == nil && voiceMemo == nil
    }

    /// Serializes everything into final comment body text. Uploads images and
    /// the voice memo to Supabase storage and appends public URLs to the body.
    func finalize(baseBody: String, postID: String) async -> String? {
        let generation = AccountStorage.generation
        let selectedImages = images
        let selectedMemo = voiceMemo
        var lines: [String] = [baseBody.trimmingCharacters(in: .whitespacesAndNewlines)]

        if !selectedImages.isEmpty {
            let datas: [Data] = await Task.detached(priority: .userInitiated) {
                selectedImages.compactMap { $0.jpegData(compressionQuality: 0.82) }
            }.value
            guard !Task.isCancelled, generation == AccountStorage.generation, datas.count == selectedImages.count else { return nil }
            let urls = await WhisperBackendService.shared.uploadMedia(
                datas: datas,
                postID: "\(postID)/c/\(UUID().uuidString.prefix(8))"
            )
            guard !Task.isCancelled, generation == AccountStorage.generation, urls.count == selectedImages.count else { return nil }
            for u in urls { lines.append(u) }
        }
        if let gif = gifURL {
            lines.append(gif.absoluteString)
        }
        if let sticker = stickerURL {
            lines.append(sticker.absoluteString)
        }
        if let poll {
            lines.append("📊 \(poll.question)")
            for opt in poll.cleanOptions { lines.append("• \(opt)") }
        }
        if let location {
            lines.append("📍 \(location)")
        }
        if let memo = selectedMemo {
            if let publicURL = await WhisperBackendService.shared.uploadAudio(
                data: memo.data,
                postID: "\(postID)/c/\(UUID().uuidString.prefix(8))",
                fileExtension: "m4a"
            ) {
                lines.append("🎙️ Voice memo (\(memo.durationString)) \(publicURL)")
            } else {
                return nil
            }
        }

        guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
        return lines
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

struct WhisperPollDraft: Equatable {
    var question: String
    var options: [String]

    var cleanOptions: [String] {
        options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isValid: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        cleanOptions.count >= 2
    }
}

struct WhisperVoiceMemoAttachment: Equatable {
    let data: Data
    let duration: TimeInterval

    var durationString: String {
        let s = Int(duration.rounded())
        return String(format: "0:%02d", min(s, 599))
    }
}

// MARK: - Attachment chips strip

/// Compact row that renders one removable chip per active attachment. Sits
/// above the text field in both composers so the user can see what's queued
/// to send and clear individual items.
struct WhisperComposerAttachmentChips: View {
    @Bindable var bag: WhisperComposerAttachments
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if bag.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(bag.images.enumerated()), id: \.offset) { idx, img in
                        thumbnailChip(image: img) {
                            bag.images.remove(at: idx)
                        }
                    }
                    if let gif = bag.gifURL {
                        animatedChip(url: gif, badge: "GIF") {
                            bag.gifURL = nil
                        }
                    }
                    if let sticker = bag.stickerURL {
                        animatedChip(url: sticker, badge: "STICKER") {
                            bag.stickerURL = nil
                        }
                    }
                    if let poll = bag.poll {
                        labelChip(
                            label: poll.question.isEmpty ? "Poll" : poll.question,
                            systemImage: "chart.bar.xaxis"
                        ) {
                            bag.poll = nil
                        }
                    }
                    if let loc = bag.location {
                        labelChip(label: loc, systemImage: "location.fill") {
                            bag.location = nil
                        }
                    }
                    if let memo = bag.voiceMemo {
                        labelChip(label: "Voice · \(memo.durationString)", systemImage: "waveform") {
                            bag.voiceMemo = nil
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
        }
    }

    /// Animated GIF / sticker thumbnail chip — uses a real `WKWebView` so
    /// the GIF actually plays inside the composer, not just a static frame.
    private func animatedChip(url: URL, badge: String, remove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            WhisperAnimatedGIFView(url: url, contentMode: .fill)
                .frame(width: 90, height: 90)
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(badge)
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.65)))
                        .padding(6)
                }
            removeButton(action: remove)
                .offset(x: 5, y: -5)
        }
        .accessibilityLabel("\(badge) \(url.absoluteString)")
    }

    private func thumbnailChip(image: UIImage, remove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
                }
            removeButton(action: remove)
                .offset(x: 5, y: -5)
        }
    }

    private func urlChip(label: String, systemImage: String, remove: @escaping () -> Void) -> some View {
        labelChip(label: label, systemImage: systemImage, remove: remove)
    }

    private func labelChip(label: String, systemImage: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(WhisperTheme.ink(colorScheme))
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(WhisperTheme.card(colorScheme))
        )
        .overlay {
            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
        .overlay(alignment: .trailing) {
            removeButton(action: remove)
                .padding(.trailing, -4)
        }
        .padding(.trailing, 14) // give room for the trailing remove button
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.black.opacity(0.7)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Camera picker

/// Thin UIKit bridge so the camera icon can present a real
/// `UIImagePickerController` on a device. On the cloud simulator the camera
/// hardware isn't available, so callers must guard with
/// `UIImagePickerController.isSourceTypeAvailable(.camera)` before presenting.
struct WhisperCameraPicker: UIViewControllerRepresentable {
    var onCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: WhisperCameraPicker
        init(_ parent: WhisperCameraPicker) { self.parent = parent }

        nonisolated func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            Task { @MainActor in
                if let image { self.parent.onCaptured(image) }
                self.parent.dismiss()
            }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in self.parent.dismiss() }
        }
    }
}

// MARK: - Emoji / sticker panel

/// Sticker sheet: a single scrolling grid of common reaction emoji. Tapping
/// one appends it to the bound draft text and dismisses.
struct WhisperEmojiPickerSheet: View {
    @Binding var draft: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let stickers: [String] = [
        "💪","🔥","🏋️‍♀️","🏋️‍♂️","🏃","🏃‍♀️","🚴","🚴‍♀️","🧘","🧘‍♀️","🤸","⛹️","🏊","🏄","⚽️","🏀",
        "🎯","🥇","🏆","🥗","🥑","🍳","🥩","🍎","🍌","🍓","💧","☕️","💤","😤","😅","🥵",
        "😎","🙌","👏","👍","🫶","❤️","🧡","💛","💚","💙","💜","🖤","🤍","✨","🌟","⚡️",
        "💯","🚀","📈","📊","⏱️","🩹","🆗","✅","❌","➡️","⬆️","🔁","🤝","🫡","🙃","😂"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 10) {
                    ForEach(stickers, id: \.self) { sticker in
                        Button {
                            Haptics.tap()
                            draft.append(sticker)
                            dismiss()
                        } label: {
                            Text(sticker)
                                .font(.system(size: 28))
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(WhisperTheme.surface(colorScheme))
            .navigationTitle("Stickers")
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
    }
}

// MARK: - Poll composer

struct WhisperPollComposerSheet: View {
    @Binding var poll: WhisperPollDraft?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var question: String = ""
    @State private var options: [String] = ["", ""]

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("Ask something…", text: $question, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("Options") {
                    ForEach(Array(options.indices), id: \.self) { idx in
                        HStack {
                            TextField("Option \(idx + 1)", text: Binding(
                                get: { options[idx] },
                                set: { options[idx] = $0 }
                            ))
                            if options.count > 2 {
                                Button {
                                    options.remove(at: idx)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if options.count < 4 {
                        Button {
                            options.append("")
                        } label: {
                            Label("Add option", systemImage: "plus.circle.fill")
                        }
                    }
                }
            }
            .navigationTitle("Poll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let draft = WhisperPollDraft(question: question, options: options)
                        guard draft.isValid else { return }
                        poll = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!WhisperPollDraft(question: question, options: options).isValid)
                }
            }
            .onAppear {
                if let existing = poll {
                    question = existing.question
                    options = existing.options.isEmpty ? ["", ""] : existing.options
                }
            }
        }
    }
}

// MARK: - Animated GIF view

/// Plays an animated GIF inside SwiftUI by hosting a `WKWebView`. SwiftUI's
/// built-in `AsyncImage` only decodes a single frame from a GIF, so we use a
/// tiny HTML shell to let the platform play the animation properly. Used
/// both for GIF / sticker preview chips and for the GIF / sticker picker
/// grid so users can see exactly what they're attaching before sending.
struct WhisperAnimatedGIFView: UIViewRepresentable {
    let url: URL
    var contentMode: ContentMode = .fill
    /// When false, the underlying `WKWebView` is fully non-interactive so
    /// taps reach the SwiftUI Button hosting the GIF (picker grids,
    /// in-canvas story sticker thumbs). `.allowsHitTesting(false)` alone
    /// isn't enough — WKWebView installs its own gesture recognizers that
    /// can swallow taps before SwiftUI can route them.
    var allowsInteraction: Bool = false

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        Self.forceTransparent(webView)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bouncesZoom = false
        webView.isUserInteractionEnabled = allowsInteraction
        webView.navigationDelegate = context.coordinator
        // Stay invisible until the GIF actually paints — prevents the
        // iOS 26 `systemFill` (pale yellow) backing view from flashing
        // through before our `clearAll` walk catches the late subviews.
        webView.alpha = 0
        return webView
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var renderedKey: String? = nil
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            WhisperAnimatedGIFView.clearAllExposed(webView)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Subviews are added asynchronously as the GIF decodes — clear
            // again on the next two runloop passes to catch late additions,
            // then fade the view in once the background is truly clear.
            WhisperAnimatedGIFView.clearAllExposed(webView)
            DispatchQueue.main.async { WhisperAnimatedGIFView.clearAllExposed(webView) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                WhisperAnimatedGIFView.clearAllExposed(webView)
                UIView.animate(withDuration: 0.18) { webView.alpha = 1 }
            }
        }
    }

    /// Public-ish entry so the Coordinator can re-clear after navigation.
    static func clearAllExposed(_ view: UIView) { clearAll(view) }

    /// Recursively wipe every layer/view background under WKWebView. On
        /// iOS 26 the web content host view (`WKContentView`) and the
        /// scroll view's internal `_UIScrollViewBackgroundView` both
        /// default to `systemFill` (a pale yellow tint) and leak through
        /// behind transparent GIFs. Clearing the WKWebView itself isn't
        /// enough — we have to walk the entire subview tree.
    private static func forceTransparent(_ webView: WKWebView) {
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        webView.layer.backgroundColor = UIColor.clear.cgColor
        clearAll(webView)
    }

    private static func clearAll(_ view: UIView) {
        view.backgroundColor = .clear
        view.layer.backgroundColor = UIColor.clear.cgColor
        for sub in view.subviews { clearAll(sub) }
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.isUserInteractionEnabled = allowsInteraction
        let fit = contentMode == .fill ? "cover" : "contain"
        let key = "\(fit)|\(url.absoluteString)"
        guard context.coordinator.renderedKey != key else { return }
        context.coordinator.renderedKey = key
        Self.forceTransparent(webView)
        let html = """
        <!doctype html><html><head><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><style>
        html,body{margin:0;padding:0;background:transparent;height:100%;width:100%;overflow:hidden;}
        img{width:100%;height:100%;object-fit:\(fit);display:block;}
        </style></head><body><img src=\"\(url.absoluteString)\"/></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - GIF picker

/// Threads-style GIF picker backed by Giphy's native REST API. Categories
/// (including the Trending bucket) come straight from
/// `/v1/gifs/categories`, and the grid loads results from
/// `/v1/gifs/trending` or `/v1/gifs/search?q=<category>` depending on the
/// active chip. Typing in the search field issues a debounced search.
struct WhisperGifPickerSheet: View {
    var onPicked: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var query: String = ""
    @State private var categories: [WhisperGiphyService.Category] = [
        .init(name: "trending", displayName: "Trending")
    ]
    @State private var selected: String = "trending"
    @State private var gifs: [WhisperGif] = []
    @State private var loading: Bool = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchBar
                categoryStrip
                gifGrid
            }
            .padding(.top, 6)
            .background(WhisperTheme.surface(colorScheme))
            .navigationTitle("Add a GIF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                let fetched = await WhisperGiphyService.shared.fetchCategories()
                if !fetched.isEmpty { categories = fetched }
                await loadCategory(selected)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Search GIPHY…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { triggerSearch(immediate: true) }
                .onChange(of: query) { _, _ in triggerSearch(immediate: false) }
            if !query.isEmpty {
                Button {
                    query = ""
                    Task { await loadCategory(selected) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5) }
        .padding(.horizontal, 14)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { cat in
                    Button {
                        Haptics.tap()
                        selected = cat.name
                        query = ""
                        Task { await loadCategory(cat.name) }
                    } label: {
                        Text(cat.displayName)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(selected == cat.name && query.isEmpty
                                             ? WhisperTheme.surface(colorScheme)
                                             : WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    selected == cat.name && query.isEmpty
                                        ? WhisperTheme.ink(colorScheme)
                                        : WhisperTheme.card(colorScheme)
                                )
                            )
                            .overlay {
                                Capsule().strokeBorder(
                                    selected == cat.name && query.isEmpty
                                        ? .clear
                                        : WhisperTheme.hairline(colorScheme),
                                    lineWidth: 0.5
                                )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var gifGrid: some View {
        ScrollView {
            if loading && gifs.isEmpty {
                ProgressView()
                    .padding(.top, 40)
            } else if gifs.isEmpty {
                VStack(spacing: 6) {
                    WhisperMeetDoodle(symbol: "sparkles", height: 120)
                    Text(query.isEmpty ? "No GIFs in this category." : "No results for \u{201C}\(query)\u{201D}.")
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .padding(.top, 40)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                    spacing: 6
                ) {
                    ForEach(gifs) { gif in
                        Button {
                            Haptics.tap()
                            onPicked(gif.url)
                            dismiss()
                        } label: {
                            Color(.secondarySystemBackground)
                                .frame(height: 150)
                                .overlay {
                                    WhisperAnimatedGIFView(url: gif.url, contentMode: .fill)
                                        .allowsHitTesting(false)
                                }
                                .clipShape(.rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
    }

    private func loadCategory(_ name: String) async {
        loading = true
        gifs = []
        let results = await WhisperGiphyService.shared.fetchGifs(for: name)
        gifs = results
        loading = false
    }

    private func triggerSearch(immediate: Bool) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            Task { await loadCategory(selected) }
            return
        }
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 280_000_000)
                if Task.isCancelled { return }
            }
            loading = true
            let results = await WhisperGiphyService.shared.search(q)
            if Task.isCancelled { return }
            gifs = results
            loading = false
        }
    }
}

// MARK: - Sticker picker

/// Threads-style animated sticker picker backed by Giphy's `/v1/stickers`
/// endpoints. Same shape as the GIF picker but the grid renders against a
/// soft transparency-checker so the transparent PNG/GIF stickers read
/// correctly before they're attached.
struct WhisperStickerPickerSheet: View {
    var includesWhisperPack: Bool = false
    var onPicked: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Sentinel category name for the bundled Whisper pack. Prepended to the
    /// category strip when `includesWhisperPack` is true so users can switch
    /// between Whisper stickers and Giphy stickers in the same sheet.
    private static let jasperCategoryName: String = "__jasper__"

    @State private var query: String = ""
    @State private var categories: [WhisperGiphyService.Category] = []
    @State private var selected: String = "trending"
    @State private var stickers: [WhisperGif] = []
    @State private var loading: Bool = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchBar
                categoryStrip
                stickerGrid
            }
            .padding(.top, 6)
            .background(WhisperTheme.surface(colorScheme))
            .navigationTitle("Add a sticker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                var cats = WhisperGiphyService.shared.stickerCategories()
                if includesWhisperPack {
                    cats.insert(
                        WhisperGiphyService.Category(name: Self.jasperCategoryName, displayName: "Whisper"),
                        at: 0
                    )
                    selected = Self.jasperCategoryName
                }
                categories = cats
                await load(selected)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Search stickers\u{2026}", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { trigger(immediate: true) }
                .onChange(of: query) { _, _ in trigger(immediate: false) }
            if !query.isEmpty {
                Button {
                    query = ""
                    Task { await load(selected) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5) }
        .padding(.horizontal, 14)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { cat in
                    Button {
                        Haptics.tap()
                        selected = cat.name
                        query = ""
                        Task { await load(cat.name) }
                    } label: {
                        Text(cat.displayName)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(selected == cat.name && query.isEmpty
                                             ? WhisperTheme.surface(colorScheme)
                                             : WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    selected == cat.name && query.isEmpty
                                        ? WhisperTheme.ink(colorScheme)
                                        : WhisperTheme.card(colorScheme)
                                )
                            )
                            .overlay {
                                Capsule().strokeBorder(
                                    selected == cat.name && query.isEmpty
                                        ? .clear
                                        : WhisperTheme.hairline(colorScheme),
                                    lineWidth: 0.5
                                )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var stickerGrid: some View {
        if selected == Self.jasperCategoryName {
            AnyView(jasperGrid)
        } else {
            AnyView(giphyGrid)
        }
    }

    private var jasperGrid: some View {
        let items = WhisperStickerPack.filtered(query: query)
        return ScrollView {
            if items.isEmpty {
                VStack(spacing: 6) {
                    WhisperMeetDoodle(symbol: "face.smiling", height: 120)
                    Text("No Whisper stickers for \u{201C}\(query)\u{201D}.")
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .padding(.top, 40)
            } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(items, id: \.name) { item in
                    Button {
                        Haptics.tap()
                        if let url = URL(string: "\(WhisperStickerPack.urlScheme)://\(item.name)") {
                            onPicked(url)
                            dismiss()
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(WhisperStickerPack.assetName(for: item.name))
                                .resizable()
                                .scaledToFit()
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .frame(height: 96)
                            Text(item.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .lineLimit(1)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
                        }
                        .contentShape(.rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
            }
        }
    }

    private var giphyGrid: some View {
        ScrollView {
            if loading && stickers.isEmpty {
                ProgressView()
                    .padding(.top, 40)
            } else if stickers.isEmpty {
                VStack(spacing: 6) {
                    WhisperMeetDoodle(symbol: "face.smiling", height: 120)
                    Text(query.isEmpty ? "No stickers in this category." : "No results for \u{201C}\(query)\u{201D}.")
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .padding(.top, 40)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(stickers) { sticker in
                        Button {
                            Haptics.tap()
                            onPicked(sticker.url)
                            dismiss()
                        } label: {
                            WhisperTheme.card(colorScheme)
                                .frame(height: 110)
                                .overlay {
                                    WhisperAnimatedGIFView(url: sticker.url, contentMode: .fit)
                                        .padding(6)
                                        .allowsHitTesting(false)
                                }
                                .clipShape(.rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
    }

    private func load(_ name: String) async {
        if name == Self.jasperCategoryName {
            stickers = []
            loading = false
            return
        }
        loading = true
        stickers = []
        let results = await WhisperGiphyService.shared.fetchStickers(for: name)
        stickers = results
        loading = false
    }

    private func trigger(immediate: Bool) {
        searchTask?.cancel()
        // Whisper pack filters locally — no network request needed.
        if selected == Self.jasperCategoryName { return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            Task { await load(selected) }
            return
        }
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 280_000_000)
                if Task.isCancelled { return }
            }
            loading = true
            let results = await WhisperGiphyService.shared.searchStickers(q)
            if Task.isCancelled { return }
            stickers = results
            loading = false
        }
    }
}

// MARK: - Voice memo recorder

/// Modal recorder sheet driven by AVAudioRecorder. Records up to 60s of
/// mono AAC at 32 kbps into a temp file, then hands the bytes + duration
/// to the caller as a `WhisperVoiceMemoAttachment`.
@MainActor
final class WhisperVoiceMemoController: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var elapsed: TimeInterval = 0
    @Published var permissionDenied: Bool = false
    @Published var callBlocked: Bool = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    func start() async {
        callBlocked = WhisperCameraCallMonitor.shared.callOwnsAudio
        guard !callBlocked else { return }
        // Ask permission first.
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { ok in cont.resume(returning: ok) }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { ok in cont.resume(returning: ok) }
            }
        }
        guard granted else { permissionDenied = true; return }
        callBlocked = WhisperCameraCallMonitor.shared.callOwnsAudio
        guard !callBlocked, !Task.isCancelled else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 22050,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record(forDuration: 60)
            self.recorder = recorder
            self.fileURL = url
            self.isRecording = true
            self.elapsed = 0
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.elapsed += 0.1
                    if self.elapsed >= 60 { _ = self.stop() }
                }
            }
        } catch {
            print("[Whisper] voice recorder error: \(error)")
            isRecording = false
        }
    }

    func stop() -> WhisperVoiceMemoAttachment? {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        isRecording = false
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let duration = elapsed
        try? FileManager.default.removeItem(at: url)
        recorder = nil
        return WhisperVoiceMemoAttachment(data: data, duration: duration)
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        isRecording = false
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        recorder = nil
        elapsed = 0
    }
}

struct WhisperVoiceMemoSheet: View {
    var onCaptured: (WhisperVoiceMemoAttachment) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var ctrl = WhisperVoiceMemoController()

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(ctrl.isRecording ? Color.red.opacity(0.15) : WhisperTheme.card(colorScheme))
                        .frame(width: 180, height: 180)
                    Image(systemName: ctrl.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(ctrl.isRecording ? .red : WhisperTheme.ink(colorScheme))
                }
                Text(timeString)
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                if ctrl.callBlocked {
                    Text("Finish your call before recording a voice memo.")
                        .font(.footnote).multilineTextAlignment(.center).padding(.horizontal, 24)
                }
                if ctrl.permissionDenied {
                    Text("Microphone access denied. Enable it in Settings to record.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }
                Spacer()
                Button {
                    Haptics.tap()
                    if ctrl.isRecording {
                        if let memo = ctrl.stop() {
                            onCaptured(memo)
                            dismiss()
                        }
                    } else {
                        Task { await ctrl.start() }
                    }
                } label: {
                    Text(ctrl.isRecording ? "Stop & Attach" : "Record")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(WhisperTheme.ink(colorScheme)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .background(WhisperTheme.surface(colorScheme))
            .navigationTitle("Voice memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        ctrl.cancel()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .whisperSheetBorder()
        .onDisappear { ctrl.cancel() }
    }

    private var timeString: String {
        let s = Int(ctrl.elapsed.rounded())
        return String(format: "0:%02d", min(s, 60))
    }
}

// MARK: - Location grabber

/// Pulls the user's current city/region via the shared EmberLocationService
/// and hands the resulting label back. Surfaces an inline error if
/// permission is denied.
enum WhisperLocationGrabber {
    @MainActor
    static func fetchLabel() async -> String? {
        do {
            let ctx = try await EmberLocationService.shared.requestCurrentContext()
            let line = ctx.displayLine
            return line.isEmpty ? nil : line
        } catch {
            return nil
        }
    }
}

// MARK: - Formatting popover

/// Tiny popover that flips bold/italic markdown around the entire draft.
/// Toggling bold wraps the text in `**…**`; italic uses `_…_`.
struct WhisperFormattingPopover: View {
    @Binding var draft: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 18) {
            formatButton(label: "Bold", systemImage: "bold") {
                draft = wrap(draft, with: "**")
            }
            formatButton(label: "Italic", systemImage: "italic") {
                draft = wrap(draft, with: "_")
            }
            formatButton(label: "Strike", systemImage: "strikethrough") {
                draft = wrap(draft, with: "~~")
            }
            formatButton(label: "Quote", systemImage: "text.quote") {
                draft = quote(draft)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(WhisperTheme.surface(colorScheme))
        .presentationDetents([.height(110)])
        .presentationDragIndicator(.visible)
        .whisperSheetBorder()
    }

    private func formatButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(label)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .frame(width: 56, height: 56)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func wrap(_ s: String, with marker: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return marker + marker }
        return "\(marker)\(trimmed)\(marker)"
    }

    private func quote(_ s: String) -> String {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { "> \($0)" }.joined(separator: "\n")
    }
}
