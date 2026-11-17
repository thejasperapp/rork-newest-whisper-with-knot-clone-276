import SwiftUI

/// Persists an explicitly requested shared Knot answer in the existing
/// conversation transport so all authorized participants can reopen it.
nonisolated enum WhisperEmberAnswerEmbed {
    static let prefix = "::whisper-ember-answer-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let question: String
        let answer: String
        let sources: [String]
        let tldr: String?
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return payload
    }
}

struct WhisperEmberAnswerInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperEmberAnswerEmbed.Payload
    let mine: Bool

    @State private var expanded: Bool = false

    /// Anything longer than this many characters in the answer is collapsed
    /// behind a "Tell me more" button so the card never takes over the
    /// entire chat screen.
    private static let collapseThreshold: Int = 280

    private var isLong: Bool { payload.answer.count > Self.collapseThreshold }

    private var preview: String {
        guard isLong else { return payload.answer }
        let firstParagraph = payload.answer
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? payload.answer
        if firstParagraph.count <= 220 { return firstParagraph }
        let idx = firstParagraph.index(firstParagraph.startIndex, offsetBy: 220)
        return String(firstParagraph[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                WhisperKnotProfilePortrait(size: 30)
                WhisperKnotWordmark()
                Spacer(minLength: 0)
            }
            Text(payload.question)
                .font(.caption.weight(.semibold))
                .opacity(0.75)
                .lineLimit(2)
            WhisperEmberRichText(text: WhisperKnotOutput.clean(payload.answer), onDark: colorScheme == .dark, baseSize: 16, inkOverride: WhisperTheme.ink(colorScheme))
                .textSelection(.enabled)
            if !payload.answer.isEmpty {
                Button {
                    Haptics.tap()
                    expanded = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.alignleft")
                            .font(.caption2.weight(.bold))
                        Text("Open answer")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 44)
                    .background(
                        WhisperTheme.surface(colorScheme),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().strokeBorder(
                            WhisperTheme.hairline(colorScheme),
                            lineWidth: 1
                        )
                    }
                }
                .buttonStyle(.plain)
            }
            if !payload.sources.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sources")
                        .font(.caption2.weight(.heavy))
                        .opacity(0.7)
                    ForEach(payload.sources.prefix(3), id: \.self) { src in
                        if let url = URL(string: src) {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                        .font(.caption2)
                                    Text(displayHost(src))
                                        .font(.caption2.weight(.semibold))
                                        .underline()
                                        .lineLimit(1)
                                }
                            }
                            .tint(.blue)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .foregroundStyle(WhisperTheme.ink(colorScheme))
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75) }
        .sheet(isPresented: $expanded) {
            WhisperEmberAnswerFullSheet(payload: payload)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .whisperSheetBorder()
        }
    }

    private func displayHost(_ url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

private struct WhisperEmberAnswerFullSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let payload: WhisperEmberAnswerEmbed.Payload

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WhisperJasperIntelligencePill(compact: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                    Text(payload.question)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    WhisperEmberRichText(text: WhisperKnotOutput.clean(payload.answer), onDark: colorScheme == .dark, baseSize: 16, inkOverride: WhisperTheme.ink(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if !payload.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sources")
                                .font(.caption.weight(.heavy))
                                .opacity(0.7)
                            ForEach(payload.sources.prefix(6), id: \.self) { src in
                                if let url = URL(string: src) {
                                    Link(destination: url) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "link")
                                                .font(.caption2)
                                            Text(URL(string: src)?.host?.replacingOccurrences(of: "www.", with: "") ?? src)
                                                .font(.footnote.weight(.semibold))
                                                .underline()
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .background(WhisperTheme.surface(colorScheme))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = payload.answer
                        Haptics.success()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}
