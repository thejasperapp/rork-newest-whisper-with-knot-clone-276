import CoreGraphics

/// Normalized top-left cells are shared by capture preview, grid glyphs and export.
nonisolated enum WhisperCaptureGrid: String, CaseIterable, Identifiable {
    case four, stacked, thirds, feature, six, sideBySide
    var id: String { rawValue }
    var title: String {
        switch self {
        case .four: "Four photos"
        case .stacked: "Two stacked"
        case .thirds: "Three stacked"
        case .feature: "One large, two small"
        case .six: "Six photos"
        case .sideBySide: "Side by side"
        }
    }
    var cells: [CGRect] {
        switch self {
        case .four: return Self.regular(columns: 2, rows: 2)
        case .stacked: return Self.regular(columns: 1, rows: 2)
        case .thirds: return Self.regular(columns: 1, rows: 3)
        case .six: return Self.regular(columns: 2, rows: 3)
        case .sideBySide: return Self.regular(columns: 2, rows: 1)
        case .feature: return [CGRect(x: 0, y: 0, width: 1, height: 0.5), CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]
        }
    }
    private static func regular(columns: Int, rows: Int) -> [CGRect] {
        (0..<(columns * rows)).map { i in
            CGRect(x: CGFloat(i % columns) / CGFloat(columns), y: CGFloat(i / columns) / CGFloat(rows), width: 1 / CGFloat(columns), height: 1 / CGFloat(rows))
        }
    }
}
