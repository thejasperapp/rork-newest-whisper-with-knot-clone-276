import SwiftUI

// MARK: - Vitality blob (bioage look)

/// Jasper's biological-age hero, drawn from the live `look` spec: a soft
/// morphing 3-layer organic blob whose palette lerps green → teal → red with
/// vitality (delta_years). 30fps Canvas per the spec ("30fps is plenty");
/// static under Reduce Motion ("static frames are fine for cards").
struct JasperVitalityBlob: View {
    let deltaYears: Double?
    let size: CGFloat
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct BlobLayer {
        let scale: Double
        let phase: Double
        let opacity: Double
        let speed: Double
    }

    private static let defaultLayers: [BlobLayer] = [
        BlobLayer(scale: 0.96, phase: 0.0, opacity: 0.30, speed: 0.60),
        BlobLayer(scale: 0.86, phase: 1.7, opacity: 0.45, speed: 0.90),
        BlobLayer(scale: 0.74, phase: 3.3, opacity: 0.95, speed: 1.25),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, canvasSize in
                let time = reduceMotion ? 1.8 : timeline.date.timeIntervalSinceReferenceDate
                draw(in: &context, canvasSize: canvasSize, time: time)
            }
        }
        .frame(width: size * 1.35, height: size * 1.35)
        .allowsHitTesting(false)
        .task { await JasperLookStore.shared.refreshIfStale() }
    }

    private func draw(in ctx: inout GraphicsContext, canvasSize: CGSize, time: Double) {
        let look = JasperLookStore.shared.look("bioage")
        let geometry = look?.look("geometry")
        let t = JasperVitalityPalette.vitalityT(deltaYears: deltaYears)
        let stops = JasperVitalityPalette.stops(t: t)
        guard stops.count == 3 else { return }

        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let radius = min(canvasSize.width, canvasSize.height) / 2 / 1.35

        let wobbleSpec = geometry?.look("wobble")
        let wobble = compact ? (wobbleSpec?.double("compact") ?? 0.55)
                             : (wobbleSpec?.double("hero") ?? 1.0)

        // Radial glow behind: stop1 @ 55% → stop2 @ 18% → transparent, ~1.5R.
        let glowGradient = Gradient(stops: [
            .init(color: stops[0].opacity(0.55), location: 0),
            .init(color: stops[1].opacity(0.18), location: 0.55),
            .init(color: .clear, location: 1),
        ])
        ctx.drawLayer { g in
            g.addFilter(.blur(radius: radius * 0.20))
            let glowRect = CGRect(x: center.x - 1.5 * radius, y: center.y - 1.5 * radius,
                                  width: 3 * radius, height: 3 * radius)
            g.fill(Path(ellipseIn: glowRect),
                   with: .radialGradient(glowGradient, center: center,
                                         startRadius: 0, endRadius: 1.5 * radius))
        }

        // The 3 breathing layers, each filled with the lerped linear gradient
        // top-left → bottom-right, softened ~2px hero / 1px compact.
        let blobRect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: 2 * radius, height: 2 * radius)
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: stops),
            startPoint: CGPoint(x: blobRect.minX, y: blobRect.minY),
            endPoint: CGPoint(x: blobRect.maxX, y: blobRect.maxY))

        ctx.drawLayer { g in
            g.addFilter(.blur(radius: compact ? 1 : 2))
            for layer in layers(from: geometry) {
                let path = Self.outline(center: center, radius: radius * layer.scale,
                                        time: time * layer.speed + layer.phase, wobble: wobble)
                g.drawLayer { gg in
                    gg.opacity = layer.opacity
                    gg.fill(path, with: shading)
                }
            }
            // The glassy core: white @ 22%, 0.42R, offset (−0.12R, −0.14R).
            let highlightCenter = CGPoint(x: center.x - 0.12 * radius, y: center.y - 0.14 * radius)
            let highlight = Self.outline(center: highlightCenter, radius: 0.42 * radius,
                                         time: time * 1.4 + 0.6, wobble: wobble * 0.8)
            g.fill(highlight, with: .color(.white.opacity(0.22)))
        }
    }

    private func layers(from geometry: JasperLook?) -> [BlobLayer] {
        guard let raw = geometry?.raw["layers"] as? [[String: Any]], !raw.isEmpty else {
            return Self.defaultLayers
        }
        let parsed: [BlobLayer] = raw.compactMap { dict in
            let l = JasperLook(raw: dict)
            guard let scale = l.double("scale"), let opacity = l.double("opacity") else { return nil }
            return BlobLayer(scale: scale, phase: l.double("phase") ?? 0,
                             opacity: opacity, speed: l.double("speed") ?? 1)
        }
        return parsed.isEmpty ? Self.defaultLayers : parsed
    }

    /// The spec's copy-paste outline, Swift-ified: a closed path of 80 points,
    /// r(θ) = R · (1 + wobble · (0.10·sin(3θ + t) + 0.06·sin(5θ − 1.3t)
    /// + 0.05·sin(2θ + 0.7t))).
    static func outline(center: CGPoint, radius: CGFloat, time: Double, wobble: Double) -> Path {
        var path = Path()
        let points = 80
        for i in 0...points {
            let theta = Double(i) / Double(points) * 2 * .pi
            let w = 0.10 * sin(3 * theta + time)
                  + 0.06 * sin(5 * theta - 1.3 * time)
                  + 0.05 * sin(2 * theta + 0.7 * time)
            let r = radius * (1 + CGFloat(wobble * w))
            let point = CGPoint(x: center.x + r * CGFloat(cos(theta)),
                                y: center.y + r * CGFloat(sin(theta)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Recovery ring (readiness look)

/// Jasper's daily-readiness hero: a thick rounded ring swept by a conic
/// mint→blue gradient with the score centered. Thresholds and colors are
/// parsed from the live `look` spec at runtime.
struct JasperRecoveryRing: View {
    let score: Int
    let size: CGFloat
    var showStatus: Bool = true

    var body: some View {
        let stroke = size * 0.094
        let colors = Self.ringColors()
        let clamped = min(100, max(0, score))
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: stroke)
            Circle()
                .trim(from: 0, to: max(0.02, CGFloat(clamped) / 100))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: colors.mint.opacity(0.85), location: 0),
                            .init(color: colors.blue.opacity(0.82), location: 0.35),
                            .init(color: colors.mint, location: 0.70),
                            .init(color: colors.mint.opacity(0.85), location: 1),
                        ]),
                        center: .center),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: colors.mint.opacity(0.45), radius: size * 0.07)
                .animation(.spring(duration: 0.8), value: clamped)
            VStack(spacing: size > 110 ? 2 : 0) {
                Text("\(clamped)")
                    .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.scoreColor(clamped))
                    .contentTransition(.numericText())
                if showStatus {
                    Text(Self.statusWord(clamped).uppercased())
                        .font(.system(size: max(7.5, size * 0.082), weight: .heavy))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .padding(stroke / 2)
        .accessibilityLabel("Readiness \(clamped) out of 100, \(Self.statusWord(clamped))")
        .task { await JasperLookStore.shared.refreshIfStale() }
    }

    static func ringColors() -> (mint: Color, blue: Color) {
        let prose = JasperLookStore.shared.look("readiness")?.proseColors("ring") ?? []
        let mint = prose.first ?? Color(jasperHex: "#5CDBB8") ?? .mint
        let blue = prose.count > 1 ? prose[1] : (Color(jasperHex: "#3394E0") ?? .blue)
        return (mint, blue)
    }

    /// score ≥ 75 → primed mint · ≥ 50 → steady blue · else run-down red,
    /// hexes + thresholds read from the spec prose.
    static func scoreColor(_ score: Int) -> Color {
        let look = JasperLookStore.shared.look("readiness")
        let hexes = look?.proseColors("score_colors") ?? []
        let nums = (look?.proseNumbers("score_colors") ?? []).filter { $0 > 1 && $0 <= 100 }
        let primed = hexes.count >= 3 ? hexes[0] : (Color(jasperHex: "#5CDBB8") ?? .mint)
        let steady = hexes.count >= 3 ? hexes[1] : (Color(jasperHex: "#3394E0") ?? .blue)
        let low = hexes.count >= 3 ? hexes[2] : (Color(jasperHex: "#F26659") ?? .red)
        let hi = nums.first ?? 75
        let mid = nums.count > 1 ? nums[1] : 50
        if Double(score) >= hi { return primed }
        if Double(score) >= mid { return steady }
        return low
    }

    static func statusWord(_ score: Int) -> String {
        let nums = (JasperLookStore.shared.look("readiness")?.proseNumbers("score_colors") ?? [])
            .filter { $0 > 1 && $0 <= 100 }
        let hi = nums.first ?? 75
        let mid = nums.count > 1 ? nums[1] : 50
        if Double(score) >= hi { return "Primed" }
        if Double(score) >= mid { return "Steady" }
        return "Run down"
    }
}

/// The readiness components — sleep / recovery / strain as small labeled
/// bars tinted by the same spec thresholds.
struct JasperReadinessBars: View {
    let sleep: Int?
    let recovery: Int?
    let strain: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            bar("SLEEP", sleep)
            bar("RECOVERY", recovery)
            bar("STRAIN", strain)
        }
    }

    @ViewBuilder
    private func bar(_ label: String, _ value: Int?) -> some View {
        if let value {
            let clamped = min(100, max(0, value))
            let tint = JasperRecoveryRing.scoreColor(clamped)
            HStack(spacing: 7) {
                Text(label)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.15))
                        Capsule().fill(tint)
                            .frame(width: max(5, geo.size.width * CGFloat(clamped) / 100))
                    }
                }
                .frame(height: 5)
                Text("\(clamped)")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .frame(width: 20, alignment: .trailing)
            }
        }
    }
}

// MARK: - Hypnogram (sleep look)

/// Jasper's night-of-sleep treatment: the four stage lanes in the exact spec
/// colors with truthfully proportional bands (the feed carries per-stage
/// totals, not segment times), the stacked night bar, the started→ended
/// axis, and quality_score in the small indigo ring.
struct JasperHypnogram: View {
    let startedAt: Date?
    let endedAt: Date?
    let awakeSeconds: Int?
    let remSeconds: Int?
    let coreSeconds: Int?
    let deepSeconds: Int?
    let qualityScore: Int?
    var compact: Bool = false

    private struct Stage: Identifiable {
        let name: String
        let seconds: Int
        let color: Color
        var id: String { name }
    }

    private var stages: [Stage] {
        let look = JasperLookStore.shared.look("sleep")?.look("stage_colors")
        func color(_ key: String, _ fallback: String) -> Color {
            look?.color(key) ?? Color(jasperHex: fallback) ?? .gray
        }
        return [
            Stage(name: "AWAKE", seconds: max(0, awakeSeconds ?? 0), color: color("awake", "#FF9500")),
            Stage(name: "REM", seconds: max(0, remSeconds ?? 0), color: color("rem", "#32ADE6")),
            Stage(name: "CORE", seconds: max(0, coreSeconds ?? 0), color: color("core", "#5856D6")),
            Stage(name: "DEEP", seconds: max(0, deepSeconds ?? 0), color: color("deep", "#AF52DE")),
        ]
    }

    private var indigo: Color {
        JasperLookStore.shared.look("sleep")?.proseColors("score").first
            ?? Color(jasperHex: "#5856D6") ?? .indigo
    }

    var body: some View {
        let all = stages
        let longest = max(1, all.map(\.seconds).max() ?? 1)
        let total = all.reduce(0) { $0 + $1.seconds }
        HStack(alignment: .center, spacing: compact ? 10 : 14) {
            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                ForEach(all) { stage in
                    lane(stage, longest: longest)
                }
                if total > 0 {
                    stackedBar(all, total: total)
                        .padding(.top, 2)
                }
                axisLine(total: total)
            }
            if let qualityScore {
                qualityRing(min(100, max(0, qualityScore)))
            }
        }
        .task { await JasperLookStore.shared.refreshIfStale() }
    }

    private func lane(_ stage: Stage, longest: Int) -> some View {
        HStack(spacing: 7) {
            Text(stage.name)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(stage.color)
                .frame(width: compact ? 34 : 40, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(stage.color.opacity(0.13))
                    if stage.seconds > 0 {
                        Capsule()
                            .fill(stage.color)
                            .frame(width: max(6, geo.size.width * CGFloat(stage.seconds) / CGFloat(longest)))
                    }
                }
            }
            .frame(height: compact ? 7 : 9)
            Text(duration(stage.seconds))
                .font(.system(size: 8.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func stackedBar(_ all: [Stage], total: Int) -> some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(all.filter { $0.seconds > 0 }) { stage in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(stage.color)
                        .frame(width: max(3, (geo.size.width - 6) * CGFloat(stage.seconds) / CGFloat(total)))
                }
            }
        }
        .frame(height: compact ? 5 : 7)
    }

    @ViewBuilder
    private func axisLine(total: Int) -> some View {
        HStack(spacing: 4) {
            if let startedAt, let endedAt {
                Text(startedAt.formatted(date: .omitted, time: .shortened))
                Image(systemName: "arrow.right")
                    .font(.system(size: 6, weight: .bold))
                Text(endedAt.formatted(date: .omitted, time: .shortened))
            }
            Spacer(minLength: 0)
            if total > 0 {
                Text("\(duration(total)) asleep + awake")
            }
        }
        .font(.system(size: 8.5))
        .foregroundStyle(.secondary.opacity(0.85))
    }

    private func qualityRing(_ quality: Int) -> some View {
        let ringSize: CGFloat = compact ? 46 : 56
        let stroke = ringSize * 0.11
        return ZStack {
            Circle().stroke(indigo.opacity(0.15), lineWidth: stroke)
            Circle()
                .trim(from: 0, to: max(0.02, CGFloat(quality) / 100))
                .stroke(indigo, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(quality)")
                    .font(.system(size: ringSize * 0.30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(indigo)
                Text("QUALITY")
                    .font(.system(size: 5.5, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityLabel("Sleep quality \(quality) out of 100")
    }

    private func duration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Ember inbox card (charts look)

/// Exactly how Jasper renders a chart posted into its Shared inbox — warm
/// cream card, ink text, the signature ember-gradient series over the last
/// 24 values, a unit chip, and the note under the chart. `kind: "bioage"`
/// earns the hourglass badge treatment.
struct JasperInboxCardPreview: View {
    let title: String
    let values: [Double]
    var labels: [String]? = nil
    var type: String = "line"
    var unit: String? = nil
    var note: String? = nil
    var kind: String = "chart"

    private var brandColors: JasperLook? {
        JasperLookStore.shared.look("brand")?.look("colors")
    }
    private var cream: Color { brandColors?.color("cream") ?? Color(jasperHex: "#FBF4E4") ?? Color(.systemBackground) }
    private var ink: Color { brandColors?.color("ink") ?? Color(jasperHex: "#211C1A") ?? .black }
    private var ember: Color { brandColors?.color("ember") ?? Color(jasperHex: "#F39057") ?? .orange }
    private var emberDeep: Color { brandColors?.color("ember_deep") ?? Color(jasperHex: "#E76F3A") ?? .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if kind == "bioage" {
                    Image(systemName: "hourglass")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(
                            LinearGradient(colors: [ember, emberDeep],
                                           startPoint: .top, endPoint: .bottom),
                            in: Circle())
                }
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(emberDeep)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ember.opacity(0.14), in: Capsule())
                }
            }

            series
                .frame(height: 104)

            if let labels, labels.count > 1, let first = labels.first, let last = labels.last {
                HStack {
                    Text(first)
                    Spacer(minLength: 0)
                    Text(last)
                }
                .font(.system(size: 9))
                .foregroundStyle(ink.opacity(0.45))
                .lineLimit(1)
            }

            if let note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(ink.opacity(0.7))
                    .lineLimit(3)
            }

            HStack(spacing: 4) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 8))
                Text("JASPER · SHARED INBOX")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.8)
            }
            .foregroundStyle(ink.opacity(0.35))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cream, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(ink.opacity(0.08), lineWidth: 1)
        }
        .task { await JasperLookStore.shared.refreshIfStale() }
    }

    /// The renderer draws the last 24 numbers as a line or bar per `type`,
    /// stroked/filled with the ember gradient.
    private var series: some View {
        Canvas { ctx, sz in
            let vals = Array(values.suffix(24))
            guard !vals.isEmpty else { return }
            let minV = vals.min() ?? 0
            let maxV = vals.max() ?? 1
            let span = max(maxV - minV, 0.0001)
            let inset: CGFloat = 4
            let w = sz.width - inset * 2
            let h = sz.height - inset * 2
            func point(_ i: Int) -> CGPoint {
                let fx = vals.count == 1 ? 0.5 : CGFloat(i) / CGFloat(vals.count - 1)
                let fy = CGFloat((vals[i] - minV) / span)
                return CGPoint(x: inset + w * fx, y: inset + h * (1 - (fy * 0.88 + 0.06)))
            }
            let gradient = Gradient(colors: [ember, emberDeep])
            if type.lowercased() == "bar" {
                let barWidth = max(3, w / CGFloat(vals.count) * 0.62)
                for i in vals.indices {
                    let p = point(i)
                    let rect = CGRect(x: p.x - barWidth / 2, y: p.y,
                                      width: barWidth, height: max(2, sz.height - inset - p.y))
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth * 0.3),
                             with: .linearGradient(gradient,
                                                   startPoint: CGPoint(x: p.x, y: rect.minY),
                                                   endPoint: CGPoint(x: p.x, y: rect.maxY)))
                }
            } else {
                var line = Path()
                for i in vals.indices {
                    let p = point(i)
                    if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                var area = line
                area.addLine(to: CGPoint(x: inset + w, y: sz.height - inset))
                area.addLine(to: CGPoint(x: inset, y: sz.height - inset))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [ember.opacity(0.22), ember.opacity(0.02)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: sz.height)))
                ctx.stroke(line,
                           with: .linearGradient(gradient,
                                                 startPoint: .zero,
                                                 endPoint: CGPoint(x: sz.width, y: sz.height)),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
