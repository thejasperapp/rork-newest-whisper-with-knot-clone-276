import SwiftUI

/// Uses the same palette and wallpaper as the live conversation.
struct WhisperChatThemePreview: View {
    let theme: WhisperChatAppearance
    var compact: Bool = false
    var design: WhisperChatThemeDesign? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = design?.palette(scheme) ?? theme.palette(scheme)
        WhisperChatWallpaper(theme: theme, design: design)
            .overlay {
                VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                    if !compact {
                        Text("TODAY · 9:41").font(.caption2.weight(.semibold)).tracking(1.4)
                            .foregroundStyle(palette.incomingText.opacity(0.7)).frame(maxWidth: .infinity)
                    }
                    previewBubble(compact ? "Hey you" : "A little change of scenery?", mine: false, palette: palette)
                    HStack { Spacer(minLength: 15); previewBubble(compact ? "Love this" : "This feels like us.", mine: true, palette: palette) }
                    if !compact {
                        previewBubble("Same conversation. A whole new mood.", mine: false, palette: palette)
                        HStack(spacing: 6) {
                            Image(systemName: "plus").frame(width: 32, height: 32).background(palette.canvas, in: .circle)
                            WhisperChatField(focused: false) {
                                HStack {
                                    Text("Message…").font(.subheadline)
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.circle.fill").foregroundStyle(palette.outgoing)
                                }.padding(12)
                            }
                        }
                        .foregroundStyle(palette.incomingText)
                        .environment(\.whisperChatAppearance, theme)
                        .environment(\.whisperChatDesign, design)
                    }
                }
                .padding(compact ? 10 : 24)
            }
            .clipShape(.rect(cornerRadius: compact ? 16 : 24))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(theme.title) conversation preview")
    }

    private func previewBubble(_ text: String, mine: Bool, palette: WhisperChatPalette) -> some View {
        Text(text).font(compact ? .system(size: 10, weight: .medium) : .subheadline)
            .foregroundStyle(palette.text(mine: mine))
            .padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 8 : 11)
            .background(palette.fill(mine: mine), in: WhisperChatStyle.shape(mine: mine, isFirstInRun: true, isLastInRun: true))
    }
}
