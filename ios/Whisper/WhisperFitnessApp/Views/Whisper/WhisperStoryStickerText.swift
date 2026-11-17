import SwiftUI

/// One text layout for the focused editor and the saved canvas layer.
struct WhisperStoryStickerText: View {
    let sticker: WhisperStorySticker
    var authoring: WhisperStoryStickerAuthoring? = nil

    var body: some View {
        let style = sticker.style ?? 0
        let ink = Color(hex: sticker.color ?? "#FFFFFF") ?? .white
        let paper = Color(hex: sticker.background ?? "#000000") ?? .black
        Group {
            if let authoring {
                TextField("", text: authoring.text, prompt: Text("Type something…").foregroundStyle(ink.opacity(0.55)), axis: .vertical)
                    .focused(authoring.focus).tint(ink).lineLimit(1...)
                    .accessibilityIdentifier("storyTextEditor")
            } else {
                Text(sticker.text ?? "")
            }
        }
        .font(WhisperStoryTypography.font(sticker.fontName, size: sticker.fontSize ?? (style == 5 ? 26 : style == 4 ? 30 : 28), style: style))
        .multilineTextAlignment(WhisperStoryTypography.alignment(sticker.textAlignment))
        .frame(maxWidth: sticker.fontName != nil ? 310 : nil)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(ink)
        .padding(.horizontal, style == 0 ? 0 : 14)
        .padding(.vertical, style == 0 ? 0 : 8)
        .background {
            switch style {
            case 1: RoundedRectangle(cornerRadius: 12, style: .continuous).fill(paper)
            case 2: RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(paper, lineWidth: 2)
            case 4: RoundedRectangle(cornerRadius: 6).fill(paper)
            case 5: RoundedRectangle(cornerRadius: 4).fill(paper.opacity(0.88))
            default: Color.clear
            }
        }
        .shadow(color: style == 0 ? .black.opacity(0.4) : .clear, radius: 4, y: 1)
        .shadow(color: style == 3 ? ink.opacity(0.9) : .clear, radius: 6)
        .shadow(color: style == 3 ? ink.opacity(0.6) : .clear, radius: 14)
    }
}
