import Foundation

/// One replaceable background per clip. Imported media stays local until the composed wave is published.
nonisolated struct WhisperWaveBackground: Codable, Equatable, Sendable {
    enum Media: String, Codable, Sendable { case photo, video }
    enum Removal: String, Codable, CaseIterable, Sendable {
        case person, chroma
        var title: String { self == .person ? "Auto person" : "Color key" }
    }
    var url: URL
    var media: Media
    var removal: Removal = .person
    var keyRed: Double = 0
    var keyGreen: Double = 1
    var keyBlue: Double = 0
    var tolerance: Double = 0.30
    var feather: Double = 0.20
    var edge: Double = 0
    var spill: Double = 0.35
    var zoom: Double = 1
    var x: Double = 0
    var y: Double = 0
    var subjectScale: Double = 1
    var subjectX: Double = 0
    var subjectY: Double = 0
    /// Background's output-clock offset. Splits retain the source-linked clock.
    var startTime: Double = 0

    static func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double = 0) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : fallback))
    }
}
