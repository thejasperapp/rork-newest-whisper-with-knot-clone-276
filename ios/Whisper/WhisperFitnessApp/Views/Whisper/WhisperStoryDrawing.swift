import SwiftUI

// MARK: - Story drawing (Instagram draw tool)
//
// Freehand strokes captured in normalized (0…1) coordinates so the same
// drawing renders identically on the editor canvas and in the baked
// composite. Three markers match the Instagram kit: pen (solid), neon
// (glowing core), and highlighter (wide translucent band).

nonisolated struct WhisperStoryDrawStroke: Codable, Identifiable, Equatable, Sendable {
    enum Marker: String, Codable, Sendable, CaseIterable {
        case pen
        case neon
        case highlighter
        case arrow
        case eraser

        var title: String { switch self { case .pen: "Pen"; case .neon: "Neon"; case .highlighter: "Marker"; case .arrow: "Arrow"; case .eraser: "Eraser" } }
        var symbol: String { switch self { case .pen: "pencil.tip"; case .neon: "lightbulb"; case .highlighter: "highlighter"; case .arrow: "arrow.up.right"; case .eraser: "eraser" } }
    }

    var id: String = UUID().uuidString
    /// Normalized points (0…1) in canvas space.
    var points: [CGPoint]
    var colorHex: String
    var width: CGFloat
    var marker: Marker
    var referenceWidth: CGFloat? = nil
}

/// Renders a stack of strokes. Used live on the editor canvas AND inside
/// the composite renderer, so what you draw is exactly what posts.
struct WhisperStoryDrawCanvas: View {
    let strokes: [WhisperStoryDrawStroke]
    let active: WhisperStoryDrawStroke?

    var body: some View {
        Canvas { context, size in
            for stroke in strokes {
                Self.draw(stroke, context: &context, size: size)
            }
            if let active {
                Self.draw(active, context: &context, size: size)
            }
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }

    static func draw(_ stroke: WhisperStoryDrawStroke, context: inout GraphicsContext, size: CGSize) {
        guard !stroke.points.isEmpty else { return }
        let width = stroke.width * size.width / max(1, stroke.referenceWidth ?? 390)
        var path = Path()
        let pts = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        path.move(to: pts[0])
        if pts.count == 1 { path.addLine(to: CGPoint(x: pts[0].x + 0.01, y: pts[0].y)) }
        else {
            for index in 1..<pts.count {
                let previous = pts[index - 1], next = pts[index]
                path.addQuadCurve(to: CGPoint(x: (previous.x + next.x) / 2, y: (previous.y + next.y) / 2), control: previous)
            }
            if let last = pts.last { path.addLine(to: last) }
        }
        if stroke.marker == .arrow, pts.count > 2, let tip = pts.last {
            let prior = pts[max(0, pts.count - 5)]
            let angle = atan2(tip.y - prior.y, tip.x - prior.x)
            let length = max(width * 3, size.width * 0.04)
            for offset in [-0.55, 0.55] {
                path.move(to: CGPoint(x: tip.x - cos(angle + offset) * length, y: tip.y - sin(angle + offset) * length))
                path.addLine(to: tip)
            }
        }
        let color = whisperColorFromHex(stroke.colorHex) ?? .white
        switch stroke.marker {
        case .eraser:
            var eraser = context
            eraser.blendMode = .destinationOut
            eraser.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: width * 2.4, lineCap: .round, lineJoin: .round))
        case .pen, .arrow:
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
        case .neon:
            var glow = context
            glow.addFilter(.blur(radius: width * 0.9))
            glow.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: width * 2.2, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                path,
                with: .color(.white),
                style: StrokeStyle(lineWidth: max(size.width / 390, width * 0.75), lineCap: .round, lineJoin: .round)
            )
        case .highlighter:
            context.stroke(
                path,
                with: .color(color.opacity(0.45)),
                style: StrokeStyle(lineWidth: width * 2.4, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

/// Parse "#RRGGBB" / "RRGGBB" into a Color. Self-contained so the drawing
/// kit has no dependency on other color helpers.
nonisolated func whisperColorFromHex(_ hex: String?) -> Color? {
    guard var s = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
    let r = Double((value >> 16) & 0xFF) / 255
    let g = Double((value >> 8) & 0xFF) / 255
    let b = Double(value & 0xFF) / 255
    return Color(red: r, green: g, blue: b)
}

/// The Instagram draw-tool color row.
let whisperStoryDrawColors: [String] = [
    "#FFFFFF", "#000000", "#FF3B30", "#FF9500", "#FFD60A",
    "#34C759", "#0A84FF", "#BF5AF2", "#FF2D92"
]
