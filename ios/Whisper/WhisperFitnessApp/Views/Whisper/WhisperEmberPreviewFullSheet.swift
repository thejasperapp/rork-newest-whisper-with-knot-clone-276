import SwiftUI

/// Scrollable full-detail sheet for the **pre-send** Jasper answer preview
/// (only the asker can see this). Mirrors the post-send `WhisperEmberAnswerFullSheet`
/// so "Tell me more" feels identical before and after sharing.
struct WhisperEmberPreviewFullSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let question: String
    let answer: String
    let sources: [String]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WhisperJasperIntelligencePill(compact: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                    if !question.isEmpty {
                        Text(question)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Text(answer)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if !sources.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sources")
                                .font(.caption.weight(.heavy))
                                .opacity(0.7)
                            ForEach(sources.prefix(6), id: \.self) { src in
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
                        UIPasteboard.general.string = answer
                        Haptics.success()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}
