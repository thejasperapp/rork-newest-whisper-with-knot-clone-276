import SwiftUI

/// Long-press peek for a grid post — Instagram-style. Pages through the whole
/// media set on its own (context-menu previews don't receive swipes), with
/// page dots, a count chip, and the caption + engagement line underneath.
/// Used by the profile grids and the feed's grid cards.
struct WhisperGridPostPeek: View {
    let urls: [URL]
    let caption: String
    let likes: Int
    let comments: Int

    @Environment(\.colorScheme) private var colorScheme
    @State private var page: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.black
                if urls.isEmpty {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.3))
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                            WhisperCachedAsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Color(white: 0.12)
                                }
                            }
                            .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .frame(width: 330, height: 330)
            .clipped()
            .overlay(alignment: .bottom) {
                if urls.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<urls.count, id: \.self) { i in
                            Circle()
                                .fill(.white.opacity(i == page ? 1 : 0.45))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(.bottom, 10)
                }
            }
            .overlay(alignment: .topTrailing) {
                if urls.count > 1 {
                    Text("\(page + 1)/\(urls.count)")
                        .font(.caption2.weight(.black))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                if WhisperPostMeta.parse(from: caption)?.hideCounts != true {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption2.weight(.bold))
                        Text("\(likes)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right.fill")
                            .font(.caption2.weight(.bold))
                        Text("\(comments)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.75))
                }
                let clean = Self.cleanCaption(caption)
                if !clean.isEmpty {
                    Text(clean)
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 330)
        .background(WhisperTheme.surface(colorScheme))
        .task { await autoAdvance() }
    }

    /// Flips through the set hands-free while the peek is held open.
    private func autoAdvance() async {
        guard urls.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                page = (page + 1) % max(urls.count, 1)
            }
        }
    }

    /// Strips any `::whisper-…` embed tokens a caption may carry so the peek
    /// never shows raw JSON.
    private static func cleanCaption(_ caption: String) -> String {
        guard caption.contains("::whisper-") else {
            return caption.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return caption
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if let r = line.range(of: "::whisper-") {
                    return String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                return String(line)
            }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
