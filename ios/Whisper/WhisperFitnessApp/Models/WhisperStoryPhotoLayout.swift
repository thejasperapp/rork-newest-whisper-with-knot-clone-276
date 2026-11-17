import Foundation
import CoreGraphics

/// Local photo arrangements. Each cell becomes an ordinary editable photo layer.
nonisolated enum WhisperStoryPhotoLayout: String, CaseIterable, Identifiable, Sendable {
    case pair, split, grid, six, strip, frame
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pair: "Two moments"
        case .split: "Side by side"
        case .grid: "Four squares"
        case .six: "Six memories"
        case .strip: "Photostrip"
        case .frame: "Frames"
        }
    }
    var cells: [CGRect] {
        switch self {
        case .pair: [CGRect(x: 0.08, y: 0.14, width: 0.84, height: 0.34), CGRect(x: 0.08, y: 0.50, width: 0.84, height: 0.34)]
        case .split: [CGRect(x: 0.04, y: 0.20, width: 0.45, height: 0.60), CGRect(x: 0.51, y: 0.20, width: 0.45, height: 0.60)]
        case .grid: Self.grid(columns: 2, rows: 2)
        case .six: Self.grid(columns: 2, rows: 3)
        case .strip: (0..<3).map { CGRect(x: 0.25, y: 0.12 + Double($0) * 0.25, width: 0.50, height: 0.23) }
        case .frame: [CGRect(x: 0.16, y: 0.24, width: 0.68, height: 0.42)]
        }
    }
    private static func grid(columns: Int, rows: Int) -> [CGRect] {
        let gap = 0.018
        let width = (0.92 - Double(columns - 1) * gap) / Double(columns)
        let height = (0.76 - Double(rows - 1) * gap) / Double(rows)
        return (0..<(columns * rows)).map { index in
            CGRect(x: 0.04 + Double(index % columns) * (width + gap), y: 0.12 + Double(index / columns) * (height + gap), width: width, height: height)
        }
    }
    func stickers(urls: [String], stageWidth: Double) -> [WhisperStorySticker] {
        zip(cells, urls).map { cell, url in
            var sticker = WhisperStorySticker(kind: .photo, x: cell.midX, y: cell.midY, imageURL: url)
            sticker.mediaAspectRatio = cell.width / (cell.height * 16 / 9)
            sticker.cardWidthFraction = cell.width
            sticker.shape = "rect"
            sticker.photoFrame = self == .frame || self == .strip
            sticker.rotation = self == .frame ? -0.06 : 0
            return sticker
        }
    }
}
