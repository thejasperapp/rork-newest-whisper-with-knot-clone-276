import SwiftUI

/// Encodes a fact-check verdict (claim + verdict + explanation + sources)
/// inside a DM body so both participants see the verdict pill and sources.
nonisolated enum WhisperFactCheckEmbed {
    static let prefix = "::whisper-factcheck-v1::"

    nonisolated enum Verdict: String, Codable, Sendable, CaseIterable {
        case trueClaim = "true"
        case mostlyTrue = "mostly_true"
        case misleading = "misleading"
        case falseClaim = "false"
        case unverified = "unverified"

        var label: String {
            switch self {
            case .trueClaim:  return "True"
            case .mostlyTrue: return "Mostly true"
            case .misleading: return "Misleading"
            case .falseClaim: return "False"
            case .unverified: return "Unverified"
            }
        }

        var tint: Color {
            switch self {
            case .trueClaim:  return .green
            case .mostlyTrue: return .mint
            case .misleading: return .orange
            case .falseClaim: return .red
            case .unverified: return .gray
            }
        }

        var symbol: String {
            switch self {
            case .trueClaim:  return "checkmark.seal.fill"
            case .mostlyTrue: return "checkmark.seal"
            case .misleading: return "exclamationmark.triangle.fill"
            case .falseClaim: return "xmark.seal.fill"
            case .unverified: return "questionmark.circle.fill"
            }
        }

        static func parse(_ raw: String) -> Verdict {
            let l = raw.lowercased()
            if l.contains("mostly") { return .mostlyTrue }
            if l.contains("mislead") { return .misleading }
            if l.contains("false") { return .falseClaim }
            if l.contains("true")  { return .trueClaim }
            return .unverified
        }
    }

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let claim: String
        let verdictRaw: String
        /// One-line punchy summary shown by default (“Short to the point”).
        let summary: String
        /// Longer explanation revealed when the user taps “Show more”.
        let explanation: String
        let sources: [String]
        var verdict: Verdict { Verdict(rawValue: verdictRaw) ?? .unverified }

        init(
            id: String,
            claim: String,
            verdictRaw: String,
            summary: String = "",
            explanation: String,
            sources: [String]
        ) {
            self.id = id
            self.claim = claim
            self.verdictRaw = verdictRaw
            self.summary = summary
            self.explanation = explanation
            self.sources = sources
        }

        nonisolated enum CodingKeys: String, CodingKey {
            case id, claim, verdictRaw, summary, explanation, sources
        }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(String.self, forKey: .id)
            self.claim = try c.decode(String.self, forKey: .claim)
            self.verdictRaw = try c.decode(String.self, forKey: .verdictRaw)
            self.summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
            self.explanation = try c.decode(String.self, forKey: .explanation)
            self.sources = (try? c.decode([String].self, forKey: .sources)) ?? []
        }
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

struct WhisperFactCheckInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperFactCheckEmbed.Payload
    let mine: Bool
    @State private var expanded: Bool = false

    /// Default-collapsed short summary (one-liner). Falls back to the first
    /// sentence of the explanation when no dedicated summary was stored.
    private var shortLine: String {
        let s = payload.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { return s }
        let trimmed = payload.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = trimmed.firstIndex(where: { ".!?".contains($0) }) {
            return String(trimmed[...end])
        }
        return trimmed
    }

    private var hasMore: Bool {
        let s = shortLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = payload.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        return !full.isEmpty && full != s || !payload.sources.isEmpty
    }

    var body: some View {
        let v = payload.verdict
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: v.symbol)
                Text(v.label.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(v.tint, in: Capsule())

            Text("\u{201C}\(payload.claim)\u{201D}")
                .font(.caption.weight(.semibold).italic())
                .opacity(0.8)
                .lineLimit(3)

            Text(shortLine)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if expanded {
                let full = payload.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
                if !full.isEmpty && full != shortLine.trimmingCharacters(in: .whitespacesAndNewlines) {
                    Text(full)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if !payload.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sources")
                            .font(.caption2.weight(.heavy))
                            .opacity(0.7)
                        ForEach(payload.sources.prefix(4), id: \.self) { src in
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
                                .tint(mine ? .white : .blue)
                            }
                        }
                    }
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if hasMore {
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "Show less" : "Show more")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption.weight(.heavy))
                    .opacity(0.75)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                WhisperEmberBadge(size: 14)
                Text("Fact-checked by Jasper")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.7)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: 280, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
        .background(
            (mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme)),
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    mine ? Color.clear : WhisperTheme.hairline(colorScheme),
                    lineWidth: 1
                )
        }
    }

    private func displayHost(_ url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}
