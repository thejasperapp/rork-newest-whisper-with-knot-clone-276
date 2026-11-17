import SwiftUI

/// A local, presentation-only classification. It never grants access or labels ordinary long text as Jasper.
struct WhisperMessageStyleGlyph: View, Equatable {
    let text: String

    var body: some View {
        let style = Self.style(for: text)
        Image(systemName: style.symbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 24)
            .accessibilityLabel(style.label)
    }

    static func style(for raw: String) -> (symbol: String, label: String) {
        guard raw.utf8.count <= 262_144 else { return ("doc", "Message") }
        let text = WhisperChatReply.split(raw).text.trimmingCharacters(in: .whitespacesAndNewlines)
        let styles: [(String, String, String)] = [
            ("::whisper-match", "heart", "Dating"),
            ("::whisper-seconddate", "calendar.badge.clock", "Date invitation"),
            ("::whisper-call", "phone", "Call"),
            ("::whisper-voice", "waveform", "Voice message"),
            ("::whisper-audio", "waveform", "Audio"),
            ("::whisper-video", "video", "Video"),
            ("::whisper-photo", "photo", "Photo"),
            ("::whisper-media", "photo.on.rectangle", "Media"),
            ("::whisper-post", "text.bubble", "Shared post"),
            ("::whisper-program", "list.clipboard", "Program"),
            ("::whisper-workout", "dumbbell", "Workout"),
            ("::whisper-proposal", "checkmark.seal", "Coach proposal"),
            ("::whisper-macro", "chart.pie", "Nutrition"),
            ("::whisper-diet", "fork.knife", "Meal plan"),
            ("::whisper-recipe", "fork.knife", "Recipe"),
            ("::whisper-grocery", "basket", "Grocery list"),
            ("::whisper-chart", "chart.bar", "Chart"),
            ("::whisper-map", "map", "Map"),
            ("::whisper-location", "mappin", "Location"),
            ("::whisper-profile", "person.crop.rectangle", "Profile"),
            ("::whisper-film", "film", "Film"),
            ("::whisper-article", "doc.richtext", "Article"),
            ("::whisper-note", "note.text", "Note"),
            ("::whisper-meeting", "video", "Meeting"),
            ("::whisper-calendar", "calendar", "Calendar event"),
            ("::whisper-poll", "chart.bar.xaxis", "Poll"),
            ("::whisper-planquiz", "questionmark.bubble", "Questionnaire"),
            ("::whisper-fact", "checkmark.seal", "Fact check"),
            ("::whisper-ember", "sparkles", "Jasper answer"),
            ("::whisper-jasper", "sparkles", "Jasper answer")
        ]
        if let style = styles.first(where: { text.hasPrefix($0.0) }) { return (style.1, style.2) }
        if WhisperStickerPack.stickerName(from: text) != nil { return ("face.smiling", "Sticker") }
        if WhisperDMThreadView.videoURL(in: text) != nil { return ("video", "Video") }
        if WhisperDMThreadView.imageURL(in: text) != nil { return ("photo", "Photo or GIF") }
        if let url = URL(string: text), url.scheme == "https", url.host != nil, !text.contains(where: \.isWhitespace) {
            return ("link", "Link")
        }
        return ("text.bubble", "Text message")
    }
}
