import SwiftUI

/// Compact action rail matching the Send tray; only distinct implemented actions are shown.
struct WhisperRepostOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: Bool = false
    @State private var generation: UUID = AccountStorage.generation
    let isReposted: Bool
    var hasMedia: Bool = true
    let onQuote: () -> Void
    let onMarkup: () -> Void
    let onUseMedia: () -> Void
    let onRepostOnly: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Text("Repost").font(.headline)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.subheadline).frame(width: 44, height: 44) }
                        .accessibilityLabel("Close repost options")
                }
                HStack(alignment: .top, spacing: 32) {
                    action(isReposted ? "Undo repost" : "Repost", symbol: "arrow.2.squarepath", perform: onRepostOnly)
                    action("Quote", symbol: "quote.bubble", perform: onQuote)
                }.frame(maxWidth: .infinity)
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }.foregroundStyle(WhisperTheme.ink(colorScheme)).buttonStyle(.plain)
            .presentationBackground(WhisperTheme.surface(colorScheme))
            .presentationDetents(typeSize.isAccessibilitySize ? [.medium, .large] : [.height(230), .large])
            .presentationContentInteraction(.scrolls).presentationDragIndicator(.visible)
            .presentationCornerRadius(WhisperMenuGeometry.sheetRadius)
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button {
            guard !selected, generation == AccountStorage.generation else { return }
            selected = true; Haptics.tap(); perform(); dismiss()
        } label: {
            VStack(spacing: 10) {
                Group {
                    if symbol == "arrow.2.squarepath" { WhisperRoundedGlyph(kind: .repost, size: 26) }
                    else { Image(systemName: symbol).font(.system(size: 25, weight: .regular)) }
                }.frame(width: 64, height: 64).background(WhisperTheme.card(colorScheme), in: .circle)
                Text(title).font(.subheadline).multilineTextAlignment(.center)
            }.frame(maxWidth: 120)
        }.disabled(selected)
    }
}
