import SwiftUI
import UIKit

// MARK: - Brain

/// Jasper's story brain — one vision call that looks at the actual canvas
/// photo and writes caption ideas + "ask your viewers" prompts for it, plus
/// a once-a-day "Today's spark" prompt that nudges people to post. Social
/// energy on purpose: Whisper is a social app, so sparks cover life, food,
/// views, music, hot takes — never fitness-coach tone unless the photo is
/// clearly a workout.
enum WhisperStoryJasperBrain {

    nonisolated struct StorySparks: Sendable {
        let captions: [String]
        let questions: [String]
    }

    private nonisolated struct SparksPayload: Decodable {
        let captions: [String]?
        let questions: [String]?
    }

    /// Reads the photo and returns 3 caption ideas + 3 viewer questions.
    static func sparks(for image: UIImage) async -> StorySparks? {
        guard RorkAIProxy.isConfigured, let dataURL = dataURL(for: image) else { return nil }

        struct VisionContent: Encodable {
            let type: String
            let text: String?
            let image_url: ImageURL?
            struct ImageURL: Encodable { let url: String }
        }
        struct VisionMessage: Encodable {
            let role: String
            let content: [VisionContent]
        }
        struct VisionRequest: Encodable {
            let model: String
            let messages: [VisionMessage]
            let max_tokens: Int
        }

        let prompt = """
        Look at this story photo and return STRICT JSON only (no prose, no code fence):
        {"captions":["…","…","…"],"questions":["…","…","…"]}
        captions: 3 short punchy story captions for THIS exact photo — ≤70 chars, no hashtags, \
        at most one emoji, three different vibes (one witty, one warm, one bold).
        questions: 3 playful "ask your viewers" prompts grounded in what's visible — ≤60 chars, \
        question form, the kind people actually answer.
        Social-app energy. Never fitness-coach tone unless the photo is clearly a workout.
        """
        let req = VisionRequest(
            model: RorkAIProxy.chatModel,
            messages: [
                VisionMessage(role: "system", content: [
                    VisionContent(type: "text", text: "You are Knot, Whisper's story sidekick. STRICT JSON only.", image_url: nil)
                ]),
                VisionMessage(role: "user", content: [
                    VisionContent(type: "text", text: prompt, image_url: nil),
                    VisionContent(type: "image_url", text: nil, image_url: .init(url: dataURL))
                ])
            ],
            max_tokens: 420
        )
        var request = RorkAIProxy.chatRequest(timeout: 40)
        guard let body = try? JSONEncoder().encode(req) else { return nil }
        request.httpBody = body
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
              let content = decoded.choices?.first?.message.content else {
            return nil
        }
        guard let payload = parseJSON(content) else { return nil }
        let captions = (payload.captions ?? []).map(clean).filter { !$0.isEmpty }.prefix(3)
        let questions = (payload.questions ?? []).map(clean).filter { !$0.isEmpty }.prefix(3)
        guard !captions.isEmpty || !questions.isEmpty else { return nil }
        return StorySparks(captions: Array(captions), questions: Array(questions))
    }

    /// One fun prompt per calendar day, cached per account so the whole day
    /// shares a single spark (and a single model call).
    static func dailySpark() async -> String {
        let today = Self.dayStamp()
        if AccountStorage.string(forKey: "whisper_story_spark_date") == today,
           let cached = AccountStorage.string(forKey: "whisper_story_spark_text"),
           !cached.isEmpty {
            return cached
        }
        let generated = await generateSpark()
        let spark = generated ?? fallbackSparks.randomElement() ?? "Show us your view right now"
        AccountStorage.set(today, forKey: "whisper_story_spark_date")
        AccountStorage.set(spark, forKey: "whisper_story_spark_text")
        return spark
    }

    private static func generateSpark() async -> String? {
        guard RorkAIProxy.isConfigured else { return nil }
        struct Message: Encodable { let role: String; let content: String }
        struct Request: Encodable { let model: String; let messages: [Message]; let max_tokens: Int }
        let req = Request(
            model: RorkAIProxy.chatModel,
            messages: [
                Message(role: "system", content: "You write ONE daily story prompt for a social app. Any topic — life, food, views, music, pets, hot takes. Not fitness-specific. ≤60 characters. Imperative or question form. No quotes, no emoji, no preamble — just the prompt."),
                Message(role: "user", content: "Today's spark (\(dayStamp())):")
            ],
            max_tokens: 40
        )
        var request = RorkAIProxy.chatRequest(timeout: 25)
        guard let body = try? JSONEncoder().encode(req) else { return nil }
        request.httpBody = body
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
              let content = decoded.choices?.first?.message.content else {
            return nil
        }
        let cleaned = clean(content)
        return cleaned.isEmpty || cleaned.count > 80 ? nil : cleaned
    }

    private static let fallbackSparks: [String] = [
        "Show us your view right now",
        "The last photo you took — no context",
        "Three emojis that sum up today",
        "What's on your desk?",
        "Your current obsession, one photo",
        "Something small that made you smile today",
        "Tonight's plans in one picture"
    ]

    private static func dayStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
    }

    private static func parseJSON(_ content: String) -> SparksPayload? {
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}") else { return nil }
        let json = String(content[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SparksPayload.self, from: data)
    }

    private static func dataURL(for image: UIImage) -> String? {
        let maxDim: CGFloat = 1024
        let largest = max(image.size.width, image.size.height)
        let scale = largest > maxDim ? maxDim / largest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}

// MARK: - Dock

/// Jasper in the story editor — the SAME meeting-style pill language as the
/// inbox/communities docks: the living mascot peeks from behind the mint
/// pill floating over the canvas; tapping it opens the dark glass box with
/// a menu of what he can do (Today's spark · Caption ideas · Ask your
/// viewers). Picking an option runs it right there and every result lands
/// on the canvas as a real draggable sticker.
struct StoryJasperDock: View {
    @Environment(\.colorScheme) private var colorScheme
    let image: UIImage
    /// Inserts a text sticker with the chosen caption.
    let onCaption: (String) -> Void
    /// Inserts a question sticker with the chosen prompt.
    let onQuestion: (String) -> Void

    private enum Panel {
        case menu, spark, captions, questions

        var title: String {
            switch self {
            case .menu: return "Story studio"
            case .spark: return "Today's spark"
            case .captions: return "Caption ideas"
            case .questions: return "Ask your viewers"
            }
        }
    }

    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panel: Panel = .menu
    @State private var mode: WhisperEmberCoachMode = WhisperEmberCoachMode.load()
    @State private var spark: String?
    @State private var sparks: WhisperStoryJasperBrain.StorySparks?
    @State private var loadingSparks = false
    @State private var failed = false
    @Namespace private var ns

    var body: some View {
        Group {
            if open {
                box
                    .whisperEdgeBack(revealPresentation: false) { if panel != .menu { panel = .menu } else { open = false } }
                    .transition(.opacity)
            } else {
                pill
            }
        }
        .onAppear {
            mode = WhisperEmberCoachMode.load()

        }
    }

    // MARK: Pill

    private var pill: some View {
        Button {
            Haptics.tap()
            mode = WhisperEmberCoachMode.load()
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { open = true }
            // The daily spark is cheap (cached per day) — warm it up so the
            // menu row can preview it.
            if spark == nil {
                Task { spark = await WhisperStoryJasperBrain.dailySpark() }
            }
        } label: {
            WhisperJasperIntelligencePill(working: loadingSparks, title: "Knot")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Knot")
        .accessibilityHint("Story captions, prompts, and questions")
        .matchedGeometryEffect(id: "storyDockHeader", in: ns, isSource: !open)

    }

    // MARK: Box

    private var box: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if panel != .menu {
                    Button {
                        Haptics.tap()
                        withAnimation(.whisperSnappy) { panel = .menu }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                            .frame(width: 22, height: 22)
                            .background(WhisperTheme.ink(colorScheme).opacity(0.06), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                VStack(alignment: .leading, spacing: 2) {
                    WhisperKnotWordmark()
                    Text(panel.title).font(.caption).foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer(minLength: 8)
                Button {
                    Haptics.tap()
                    withAnimation(.spring(duration: 0.36, bounce: 0.12)) {
                        open = false
                        panel = .menu
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                        .frame(width: 22, height: 22)
                        .background(WhisperTheme.ink(colorScheme).opacity(0.06), in: Circle())
                            .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Knot")
            }
            .padding(.leading, panel == .menu ? 16 : 8)
            .padding(.trailing, 7)
            .frame(minHeight: 54)
            .background { WhisperJasperIntelligenceShell(shape: Capsule()) }
            .matchedGeometryEffect(id: "storyDockHeader", in: ns, isSource: open)
            .padding(.horizontal, 10)
            .padding(.top, 10)

            ViewThatFits(in: .vertical) {
                contentBlock
                ScrollView(showsIndicators: false) { contentBlock }
            }
            .frame(maxHeight: 320, alignment: .top)
        }
        .frame(maxWidth: 370)
        .padding(.horizontal, 12)
        .background { WhisperJasperIntelligenceShell(shape: RoundedRectangle(cornerRadius: 24), panel: true, onDark: true) }
    }

    @ViewBuilder
    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch panel {
            case .menu: menuRows
            case .spark: sparkPanel
            case .captions: ideasPanel(items: sparks?.captions ?? [], apply: applyCaption)
            case .questions: ideasPanel(items: sparks?.questions ?? [], apply: applyQuestion)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Menu

    private var menuRows: some View {
        VStack(spacing: 6) {
            menuRow(
                icon: "flame.fill",
                title: "Today's spark",
                subtitle: spark ?? "One prompt a day — warming it up…"
            ) {
                withAnimation(.whisperSnappy) { panel = .spark }
                if spark == nil {
                    Task { spark = await WhisperStoryJasperBrain.dailySpark() }
                }
            }
            menuRow(
                icon: "text.quote",
                title: "Caption ideas",
                subtitle: "Jasper reads this exact photo — 3 vibes"
            ) {
                withAnimation(.whisperSnappy) { panel = .captions }
                ensureSparks()
            }
            menuRow(
                icon: "questionmark.bubble.fill",
                title: "Ask your viewers",
                subtitle: "Question stickers people actually answer"
            ) {
                withAnimation(.whisperSnappy) { panel = .questions }
                ensureSparks()
            }
        }
    }

    private func menuRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(mode.accent.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(mode.softAccent)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Spark panel

    private var sparkPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9, weight: .black))
                Text("TODAY'S SPARK")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
            }
            .foregroundStyle(mode.softAccent)
            Text(spark ?? "Warming one up…")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .redacted(reason: spark == nil ? .placeholder : [])
            Button {
                guard let spark else { return }
                applyCaption(spark)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.black))
                    Text("Add to story")
                        .font(.footnote.weight(.bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(.white, in: Capsule())
                .opacity(spark == nil ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(spark == nil)
            Text("One spark a day — a fresh one lands tomorrow.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(mode.accent.opacity(0.3), lineWidth: 1)
        }
    }

    // MARK: Ideas panels

    @ViewBuilder
    private func ideasPanel(items: [String], apply: @escaping (String) -> Void) -> some View {
        if items.isEmpty {
            if loadingSparks {
                VStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 44)
                            .phaseAnimator([0.45, 1.0]) { view, o in
                                view.opacity(o)
                            } animation: { _ in
                                .easeInOut(duration: 0.8)
                            }
                    }
                    Text("Jasper is reading your photo…")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(failed ? "Couldn't read the photo right now." : "No ideas yet.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                    regenerateChip
                }
            }
        } else {
            VStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Button {
                        apply(item)
                    } label: {
                        HStack(spacing: 10) {
                            Text(item)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 6)
                            Image(systemName: "plus.circle.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(mode.softAccent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    regenerateChip
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var regenerateChip: some View {
        Button {
            guard !loadingSparks else { return }
            Haptics.tap()
            sparks = nil
            ensureSparks(force: true)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                Text(loadingSparks ? "Reading…" : "New ideas")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(loadingSparks)
    }

    // MARK: Apply + load

    private func applyCaption(_ text: String) {
        Haptics.success()
        onCaption(text)
        withAnimation(.spring(duration: 0.36, bounce: 0.12)) {
            open = false
            panel = .menu
        }
    }

    private func applyQuestion(_ text: String) {
        Haptics.success()
        onQuestion(text)
        withAnimation(.spring(duration: 0.36, bounce: 0.12)) {
            open = false
            panel = .menu
        }
    }

    private func ensureSparks(force: Bool = false) {
        guard sparks == nil || force, !loadingSparks else { return }
        loadingSparks = true
        failed = false
        Task {
            let result = await WhisperStoryJasperBrain.sparks(for: image)
            await MainActor.run {
                loadingSparks = false
                if let result {
                    sparks = result
                } else {
                    failed = true
                }
            }
        }
    }

}
