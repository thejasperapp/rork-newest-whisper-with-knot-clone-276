import SwiftUI

// MARK: - Water look (catalog `looks.water`, style "water_cup" — Aug 17 2026)

/// Jasper's water-cup render spec, read live off `JasperLookStore` ("water")
/// with the published defaults as fallbacks: tapered tumbler, sine-wave fill
/// (2.6pt amplitude, 1.6 rad/s), waterTint #338FDB light / #5CB3F2 dark.
enum JasperWaterLook {
    static func tint(_ scheme: ColorScheme) -> Color {
        let spec = JasperLookStore.shared.look("water")?.look("fill")?.look("water_tint")
        let fallback = scheme == .dark
            ? Color(red: 0.361, green: 0.702, blue: 0.949)   // #5CB3F2
            : Color(red: 0.200, green: 0.561, blue: 0.859)   // #338FDB
        return spec?.color(scheme == .dark ? "dark" : "light") ?? fallback
    }

    /// Warm cream ember card the spec mounts both variants on.
    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.141, green: 0.125, blue: 0.114)   // #24201D
            : Color(red: 0.984, green: 0.957, blue: 0.894)   // #FBF4E4
    }

    static let amplitude: CGFloat = 2.6      // pt, 0 when empty
    static let omega: Double = 1.6           // rad/s (~0.25 Hz)
    static let taper: CGFloat = 0.12         // per side, × width
    static let goalMint = Color(red: 0.36, green: 0.86, blue: 0.72)
}

// MARK: - The glass (86×118 reference geometry, spec-exact)

/// The animated tumbler: top edge full width, sides taper inward by
/// width×0.12 toward the base, 10pt quad-curve base corners, 2pt outline at
/// 22% ink. Water surface is a live sine line; level changes ease in ~0.6s
/// (a static frame is a valid render — the spec says so).
struct JasperWaterCupGlass: View {
    let level: Double
    var width: CGFloat = 86
    var height: CGFloat = 118
    var showTapHint: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var fromLevel: Double
    @State private var changedAt: Date = .distantPast

    init(level: Double, width: CGFloat = 86, height: CGFloat = 118, showTapHint: Bool = false) {
        self.level = level
        self.width = width
        self.height = height
        self.showTapHint = showTapHint
        _fromLevel = State(initialValue: level)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            cupCanvas(date: context.date)
        }
        .frame(width: width, height: height)
        .onChange(of: level) { oldValue, _ in
            fromLevel = min(1, max(0, oldValue))
            changedAt = Date()
        }
        .accessibilityHidden(true)
    }

    /// Canvas hoisted out of `body` and the wave math split into small,
    /// explicitly-typed helpers — the archive compiler timed out
    /// type-checking the original single-expression version (CGFloat/Double
    /// implicit-conversion explosion).
    private func cupCanvas(date: Date) -> some View {
        Canvas { ctx, size in
            drawCup(into: &ctx, size: size, date: date)
        }
    }

    private func drawCup(into ctx: inout GraphicsContext, size: CGSize, date: Date) {
        let displayLevel: Double = easedLevel(at: date)
        let glass: Path = Self.glassPath(in: size)

        if displayLevel > 0.001 {
            fillWater(into: &ctx, size: size, date: date, displayLevel: displayLevel, glass: glass)
        }

        ctx.stroke(glass, with: .color(.primary.opacity(0.22)),
                   style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        if showTapHint, displayLevel <= 0.001 {
            let hint: Text = Text("Tap to log")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            ctx.draw(hint, at: CGPoint(x: size.width / 2, y: size.height * 0.55))
        }
    }

    private func fillWater(into ctx: inout GraphicsContext, size: CGSize, date: Date,
                           displayLevel: Double, glass: Path) {
        let tint: Color = JasperWaterLook.tint(colorScheme)
        let phase: Double = date.timeIntervalSinceReferenceDate * JasperWaterLook.omega
        let amplitude: CGFloat = displayLevel >= 0.999 ? 1.2 : JasperWaterLook.amplitude
        let surfaceY: CGFloat = size.height * CGFloat(1.0 - displayLevel)
        let water: Path = Self.waterPath(in: size, surfaceY: surfaceY,
                                         phase: phase, amplitude: amplitude)

        let stops: [Gradient.Stop] = [
            Gradient.Stop(color: tint.opacity(0.55), location: 0),
            Gradient.Stop(color: tint.opacity(0.90), location: 1),
        ]
        var inner: GraphicsContext = ctx
        inner.clip(to: glass)
        inner.fill(water, with: .linearGradient(
            Gradient(stops: stops),
            startPoint: CGPoint(x: size.width / 2, y: surfaceY),
            endPoint: CGPoint(x: size.width / 2, y: size.height)))
    }

    /// Cubic ease-out from the previous level toward the target (~0.6s).
    private func easedLevel(at date: Date) -> Double {
        let target: Double = min(1.0, max(0.0, level))
        let elapsed: Double = date.timeIntervalSince(changedAt)
        let t: Double = min(1.0, max(0.0, elapsed / 0.6))
        let eased: Double = 1.0 - pow(1.0 - t, 3.0)
        return min(1.0, max(0.0, fromLevel + (target - fromLevel) * eased))
    }

    /// Live sine surface (sampled every 3pt) closed down to the base.
    nonisolated static func waterPath(in size: CGSize, surfaceY: CGFloat,
                                      phase: Double, amplitude: CGFloat) -> Path {
        var water = Path()
        let startY: CGFloat = surfaceY + CGFloat(sin(phase)) * amplitude
        water.move(to: CGPoint(x: 0, y: startY))
        var x: CGFloat = 0
        while x <= size.width {
            let angle: Double = Double(x / size.width) * 2.0 * Double.pi + phase
            let y: CGFloat = surfaceY + CGFloat(sin(angle)) * amplitude
            water.addLine(to: CGPoint(x: x, y: y))
            x += 3
        }
        water.addLine(to: CGPoint(x: size.width, y: size.height))
        water.addLine(to: CGPoint(x: 0, y: size.height))
        water.closeSubpath()
        return water
    }

    /// Tapered tumbler with 10pt quad-curve base corners.
    nonisolated static func glassPath(in size: CGSize) -> Path {
        let inset: CGFloat = 1.5
        let taper = size.width * JasperWaterLook.taper
        let corner: CGFloat = min(10, size.height * 0.12)
        var path = Path()
        path.move(to: CGPoint(x: inset, y: inset))
        path.addLine(to: CGPoint(x: size.width - inset, y: inset))
        path.addLine(to: CGPoint(x: size.width - inset - taper, y: size.height - inset - corner))
        path.addQuadCurve(
            to: CGPoint(x: size.width - inset - taper - corner, y: size.height - inset),
            control: CGPoint(x: size.width - inset - taper, y: size.height - inset))
        path.addLine(to: CGPoint(x: inset + taper + corner, y: size.height - inset))
        path.addQuadCurve(
            to: CGPoint(x: inset + taper, y: size.height - inset - corner),
            control: CGPoint(x: inset + taper, y: size.height - inset))
        path.closeSubpath()
        return path
    }
}

// MARK: - Ring variant (compact spots — 52pt, 5pt stroke, 12 o'clock start)

struct JasperWaterRing: View {
    let count: Int
    let goal: Int
    var size: CGFloat = 52

    @Environment(\.colorScheme) private var colorScheme
    @State private var pop = false

    private var progress: Double { min(1, Double(count) / Double(max(1, goal))) }
    private var atGoal: Bool { count >= goal && goal > 0 }

    var body: some View {
        let tint = JasperWaterLook.tint(colorScheme)
        ZStack {
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(atGoal ? JasperWaterLook.goalMint : tint,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            Image(systemName: atGoal ? "checkmark.seal.fill" : "drop.fill")
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(atGoal ? JasperWaterLook.goalMint : tint)
                .scaleEffect(pop ? 1.2 : 1.0)
        }
        .frame(width: size, height: size)
        .onChange(of: count) { oldValue, newValue in
            guard newValue > oldValue else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { pop = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { pop = false }
            }
        }
        .accessibilityLabel("Water: \(count) of \(goal) cups\(atGoal ? ", goal reached" : "")")
    }
}

// MARK: - The full card (kicker · big count · glass, on the ember cream card)

/// Spec copy block: kicker "WATER" in small caps with a drop icon, the count
/// big in a bold rounded face with "of N" beside it, "+N beyond goal" past
/// the goal. Interactive when `onAdd`/`onRemove` are wired (tap the glass to
/// log one — light impact haptic; steppers beside it).
struct JasperWaterCard: View {
    let cups: Int
    let goal: Int
    var totalML: Int? = nil
    var caption: String? = nil
    var onAdd: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var glassWidth: CGFloat = 86
    var glassHeight: CGFloat = 118

    @Environment(\.colorScheme) private var colorScheme

    private var beyondGoal: Int { max(0, cups - goal) }

    var body: some View {
        let tint = JasperWaterLook.tint(colorScheme)
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint)
                    Text("WATER")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(.primary.opacity(0.55))
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(cups)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text("of \(goal)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.45))
                }
                if beyondGoal > 0 {
                    Text("+\(beyondGoal) beyond goal")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                }
                if let totalML {
                    Text("\(totalML) ml today")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.45))
                }
                if onAdd != nil || onRemove != nil {
                    HStack(spacing: 8) {
                        stepButton("minus", enabled: cups > 0) { onRemove?() }
                        stepButton("plus", enabled: true) { onAdd?() }
                    }
                    .padding(.top, 2)
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.primary.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let onAdd {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onAdd()
                } label: {
                    JasperWaterCupGlass(level: Double(cups) / Double(max(1, goal)),
                                        width: glassWidth, height: glassHeight,
                                        showTapHint: true)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log one cup of water")
            } else {
                JasperWaterCupGlass(level: Double(cups) / Double(max(1, goal)),
                                    width: glassWidth, height: glassHeight)
            }
        }
        .padding(16)
        .background(JasperWaterLook.cardFill(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: tint.opacity(colorScheme == .dark ? 0.10 : 0.14), radius: 14, y: 5)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? JasperWaterLook.tint(colorScheme) : .primary.opacity(0.25))
                .frame(width: 32, height: 32)
                .background(.primary.opacity(0.06), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Own water tracker (reads + writes the user's own Jasper)

/// The user's live water day: rows read off `/v1/water` (today), tap the
/// glass or + to log a 250 ml cup straight into Jasper, − deletes the most
/// recent cup. Rendered exactly from the water_cup spec.
struct JasperWaterTrackerSheet: View {
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private struct WaterRow: Identifiable, Equatable {
        let id: String
        let ml: Int
        let loggedAt: Date?
        var deletable: Bool
    }

    private enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var rows: [WaterRow] = []
    @State private var busy = false
    @State private var note: String?

    private let goal = 8
    private let cupML = 250

    private var totalML: Int { rows.reduce(0) { $0 + $1.ml } }
    private var cups: Int { Int((Double(totalML) / Double(cupML)).rounded()) }

    var body: some View {
        ZStack {
            JasperGlowStage()
            VStack(spacing: 0) {
                header
                switch phase {
                case .loading:
                    Spacer()
                    ProgressView().tint(JasperBrand.ember)
                    Spacer()
                case .failed(let message):
                    failedBody(message)
                case .ready:
                    readyBody
                }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                JasperKicker(text: "Water · today")
                Text("Jasper's own cup")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(JasperBrand.text(colorScheme))
            }
            Spacer()
            Button {
                Haptics.tap()
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.65))
                    .frame(width: 32, height: 32)
                    .background(JasperBrand.chip(colorScheme), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close water tracker")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var readyBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                JasperWaterCard(
                    cups: cups,
                    goal: goal,
                    totalML: totalML,
                    caption: nil,
                    onAdd: { Task { await addCup() } },
                    onRemove: rows.contains(where: \.deletable) ? { Task { await removeCup() } } : nil)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(JasperBrand.ember)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Rendered from Jasper's own water_cup spec — the same animated glass Jasper draws in-app. Every tap writes a 250 ml cup straight into your Jasper (write:nutrition); − removes the last cup.")
                    .font(.caption2)
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private func failedBody(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "drop")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(JasperBrand.kicker(colorScheme))
            Text("Couldn't read your water")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(JasperBrand.text(colorScheme))
            Text(message)
                .font(.footnote)
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Haptics.tap()
                phase = .loading
                Task { await load() }
            } label: {
                Text("Try again")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(JasperBrand.ink)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(JasperBrand.emberGradient, in: .capsule)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Data

    private func load() async {
        do {
            let since = Calendar.current.startOfDay(for: Date())
            let data = try await JasperConnectClient.shared.read("water", since: since, limit: 200)
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let raw = (body?["data"] as? [[String: Any]]) ?? []
            rows = raw.compactMap { row in
                let ml = (row["amount_ml"] as? NSNumber)?.intValue ?? 0
                guard ml > 0 else { return nil }
                let id = (row["id"] as? String) ?? (row["id"] as? NSNumber).map { "\($0)" }
                return WaterRow(id: id ?? UUID().uuidString, ml: ml,
                                loggedAt: jasperConnectDate(row["logged_at"]),
                                deletable: id != nil)
            }
            .sorted { ($0.loggedAt ?? .distantPast) < ($1.loggedAt ?? .distantPast) }
            withAnimation(.spring(duration: 0.35)) { phase = .ready }
        } catch JasperConnectError.notConnected {
            phase = .failed("Connect Jasper first — Settings → Sync with Jasper, one tap.")
        } catch {
            phase = .failed((error as? JasperConnectError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func addCup() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        note = nil
        do {
            let receipt = try await JasperConnectClient.shared.post("water", [
                "amount_ml": cupML,
                "logged_at": ISO8601DateFormatter().string(from: Date()),
            ])
            let id = receipt.id?.uuidString ?? receipt.clientID ?? UUID().uuidString
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                rows.append(WaterRow(id: id, ml: cupML, loggedAt: Date(),
                                     deletable: receipt.id != nil || receipt.clientID != nil))
            }
            Haptics.success()
        } catch {
            Haptics.warning()
            note = "That cup didn't reach Jasper — \((error as? JasperConnectError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func removeCup() async {
        guard !busy, let last = rows.last(where: \.deletable) else { return }
        busy = true
        defer { busy = false }
        note = nil
        do {
            try await JasperConnectClient.shared.deleteRow(resource: "water", id: last.id)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                rows.removeAll { $0.id == last.id }
            }
            Haptics.tap()
        } catch {
            Haptics.warning()
            note = "Couldn't remove that cup — \((error as? JasperConnectError)?.errorDescription ?? error.localizedDescription)"
        }
    }
}
