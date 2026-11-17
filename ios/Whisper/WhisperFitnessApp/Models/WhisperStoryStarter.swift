import Foundation

/// Authored editable type compositions, separate from network participation prompts.
nonisolated enum WhisperStoryStarter: String, CaseIterable, Identifiable, Sendable {
    case month, daily, postcard, moments, question, poll
    var id: String { rawValue }
    var title: String {
        switch self {
        case .month: "Month so far"
        case .daily: "Today, in a few words"
        case .postcard: "Somewhere good"
        case .moments: "Little moments"
        case .question: "Ask me anything"
        case .poll: "This or that"
        }
    }
    var subtitle: String { self == .question || self == .poll ? "Make it a conversation" : "Editable text · your own photos" }
    var backgroundHex: String {
        switch self {
        case .month: "#222922"
        case .daily: "#744C38"
        case .postcard: "#254654"
        case .moments: "#66493D"
        case .question: "#263C34"
        case .poll: "#3C3542"
        }
    }
    func stickers(date: Date = .now) -> [WhisperStorySticker] {
        func text(_ value: String, y: Double, font: String = "editorial", size: Double = 48, rotation: Double = 0) -> WhisperStorySticker {
            var layer = WhisperStorySticker(kind: .text, y: y, rotation: rotation * .pi / 180, text: value, color: "#FFF7BD", style: 0)
            layer.fontName = font; layer.fontSize = size
            return layer
        }
        switch self {
        case .month:
            return [text(date.formatted(.dateTime.month(.wide)).uppercased(), y: 0.32, size: 39), text("SO", y: 0.50), text("FAR", y: 0.68)]
        case .daily:
            return [text(date.formatted(.dateTime.month(.abbreviated).day()).uppercased(), y: 0.23, font: "typewriter", size: 17), text("today,\nin a few words.", y: 0.49, font: "serif", size: 38), text("a little life lately", y: 0.78, font: "typewriter", size: 14)]
        case .postcard:
            return [text("POSTCARD", y: 0.20, size: 43), text("from somewhere good", y: 0.76, font: "serif", size: 24, rotation: -4)]
        case .moments:
            return [text("LITTLE", y: 0.23, size: 44), text("MOMENTS", y: 0.32, size: 40), text("worth keeping.", y: 0.79, font: "serif", size: 28)]
        case .question:
            return [WhisperStorySticker(kind: .question, y: 0.60, text: "What's one thing I should try?", color: "#252525", background: "#FFFFFF")]
        case .poll:
            return [WhisperStorySticker(kind: .poll, y: 0.60, text: "What's the plan?", pollOptions: ["A night in", "An adventure"])]
        }
    }
}
