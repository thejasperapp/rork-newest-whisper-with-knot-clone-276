import Foundation
import UIKit

/// One transcribed word, timed in its source file's own seconds. Keying by
/// file rather than clip means trims, splits, reorders and duplicates never
/// need the words touched — the composition maps them onto the output clock.
nonisolated struct WhisperWaveCaptionWord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var url: URL
    var start: Double
    var end: Double
}

/// The caption looks — TikTok / CapCut's word-by-word families, on-device.
nonisolated enum WhisperWaveCaptionStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Whole phrase; the spoken word pops in the highlight color.
    case pop
    /// Whole phrase in bold caps; the spoken word sits on a colored plate.
    case box
    /// One big word at a time.
    case solo
    /// Classic subtitles on a soft black plate — no word highlight.
    case classic
    /// White fill with a dark outline; the spoken word tints.
    case outline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pop: return "Pop"
        case .box: return "Box"
        case .solo: return "Solo"
        case .classic: return "Classic"
        case .outline: return "Outline"
        }
    }

    var systemImage: String {
        switch self {
        case .pop: return "textformat.abc"
        case .box: return "character.textbox"
        case .solo: return "textformat.size.larger"
        case .classic: return "captions.bubble"
        case .outline: return "a.square"
        }
    }

    var highlightsWords: Bool { self != .classic }
    var font: WaveTextFont {
        switch self {
        case .pop, .outline: return .classic
        case .box, .solo: return .strong
        case .classic: return .neon
        }
    }
}

/// The wave's captions: every transcribed word plus one look for all of them.
nonisolated struct WhisperWaveCaptions: Codable, Equatable, Sendable {
    var words: [WhisperWaveCaptionWord]
    var style: WhisperWaveCaptionStyle
    /// Hex of the spoken-word color.
    var highlightHex: String
    /// Normalized vertical center of the caption block, 0 = top.
    var y: Double
    /// Size multiplier 0.7 … 1.6.
    var scale: Double
    /// BCP-47 tag of the language recognized.
    var language: String

    init(words: [WhisperWaveCaptionWord], style: WhisperWaveCaptionStyle = .pop, highlightHex: String = "FFC94D", y: Double = 0.74, scale: Double = 1, language: String) {
        self.words = words
        self.style = style
        self.highlightHex = highlightHex
        self.y = y
        self.scale = scale
        self.language = language
    }

    static let highlightHexes: [String] = ["FFC94D", "FF7340", "9BE8C4", "FF4D8D", "38BDF8", "FFFFFF"]

    var clampedScale: Double { min(1.6, max(0.7, scale.isFinite ? scale : 1)) }
    var clampedY: Double { min(0.92, max(0.1, y.isFinite ? y : 0.74)) }
    var highlightColor: UIColor { WaveTextPalette.uiColor(highlightHex) }

    /// The words that land on the wave's output clock, given the current clips.
    func placed(in clips: [WhisperWaveClip]) -> [WhisperWaveCaptionPlacedWord] {
        var result: [WhisperWaveCaptionPlacedWord] = []
        for clip in clips {
            let start = WhisperWaveTimeline.start(of: clip.id, in: clips)
            result.append(contentsOf: Self.place(words, on: clip, outputStart: start))
        }
        return result.sorted { $0.start < $1.start }
    }

    /// Words of `clip`'s file inside its trim window, on the output clock.
    static func place(_ words: [WhisperWaveCaptionWord], on clip: WhisperWaveClip, outputStart: Double) -> [WhisperWaveCaptionPlacedWord] {
        let speed = max(0.1, clip.speed)
        return words.compactMap { word in
            guard word.url.path == clip.url.path, word.end > clip.trimStart, word.start < clip.trimEnd else { return nil }
            let start = outputStart + (max(word.start, clip.trimStart) - clip.trimStart) / speed
            let end = outputStart + (min(word.end, clip.trimEnd) - clip.trimStart) / speed
            guard end > start else { return nil }
            return WhisperWaveCaptionPlacedWord(id: word.id, text: word.text, start: start, end: end, clipID: clip.id)
        }
    }

    /// Rewrites one phrase's words from edited text, spreading the new words
    /// across the phrase's original source time by their length.
    mutating func replace(phrase: WhisperWaveCaptionPhrase, with text: String) {
        let pieces = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        let ids = Set(phrase.words.map(\.id))
        let originals = words.filter { ids.contains($0.id) }.sorted { $0.start < $1.start }
        guard let first = originals.first, let last = originals.last, let insertAt = words.firstIndex(where: { $0.id == first.id }) else { return }
        words.removeAll { ids.contains($0.id) }
        guard !pieces.isEmpty else { return }
        let span = max(0.2, last.end - first.start)
        let weights = pieces.map { Double(max(1, $0.count)) }
        let total = weights.reduce(0, +)
        var cursor = first.start
        var replacement: [WhisperWaveCaptionWord] = []
        for (piece, weight) in zip(pieces, weights) {
            let length = span * weight / total
            replacement.append(WhisperWaveCaptionWord(text: piece, url: first.url, start: cursor, end: cursor + length))
            cursor += length
        }
        words.insert(contentsOf: replacement, at: min(insertAt, words.count))
    }

    mutating func remove(phrase: WhisperWaveCaptionPhrase) {
        let ids = Set(phrase.words.map(\.id))
        words.removeAll { ids.contains($0.id) }
    }
}

/// A word on the output clock.
nonisolated struct WhisperWaveCaptionPlacedWord: Equatable, Sendable, Identifiable {
    let id: UUID
    let text: String
    let start: Double
    let end: Double
    let clipID: UUID
}

/// A short run of words shown together — broken at pauses, sentence ends,
/// clip boundaries and a word budget so each fits a phone screen.
nonisolated struct WhisperWaveCaptionPhrase: Equatable, Sendable, Identifiable {
    let words: [WhisperWaveCaptionPlacedWord]
    /// Seconds the phrase stays up after its last word, until the next one.
    let displayEnd: Double

    var id: UUID { words.first?.id ?? UUID() }
    var start: Double { words.first?.start ?? 0 }
    var end: Double { words.last?.end ?? 0 }
    var text: String { words.map(\.text).joined(separator: " ") }

    /// Groups placed words into phrases.
    static func phrases(_ words: [WhisperWaveCaptionPlacedWord], maxWords: Int = 5, maxCharacters: Int = 26, pause: Double = 0.55) -> [WhisperWaveCaptionPhrase] {
        var groups: [[WhisperWaveCaptionPlacedWord]] = []
        var current: [WhisperWaveCaptionPlacedWord] = []
        var characters = 0
        for word in words {
            let breaks: Bool
            if let last = current.last {
                let gap = word.start - last.end
                let sentenceEnd = last.text.last.map { ".!?".contains($0) } ?? false
                breaks = gap > pause || sentenceEnd || last.clipID != word.clipID || current.count >= maxWords || characters + word.text.count + 1 > maxCharacters
            } else {
                breaks = false
            }
            if breaks, !current.isEmpty {
                groups.append(current)
                current = []
                characters = 0
            }
            current.append(word)
            characters += word.text.count + (current.count > 1 ? 1 : 0)
        }
        if !current.isEmpty { groups.append(current) }
        var result: [WhisperWaveCaptionPhrase] = []
        for (index, group) in groups.enumerated() {
            guard let last = group.last else { continue }
            let next = index + 1 < groups.count ? groups[index + 1].first?.start : nil
            let hold = last.end + 0.9
            result.append(WhisperWaveCaptionPhrase(words: group, displayEnd: next.map { min($0, hold) } ?? hold))
        }
        return result
    }
}
