import SwiftUI

/// The Photos-app adjustment dial: a ticked ruler that slides beneath a fixed
/// accent needle. Drag the ruler left for more and right for less; every tick
/// clicks, detents knock and hold, and a double tap returns to the default.
struct WhisperWaveRuler: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    /// Value distance between ticks — one click per tick.
    var tick: Double = 0.05
    /// Magnetic stops that snap and knock a little harder.
    var detents: [Double] = []
    /// Points of ruler travel per unit of value.
    var pointsPerUnit: CGFloat = 220
    /// Caption on the left; empty hides the caption row's label.
    var label: String = ""
    var format: (Double) -> String = { String(format: "%.0f", $0 * 100) }
    var onEditingChanged: ((Bool) -> Void)? = nil
    @State private var dragStart: Double?
    @State private var lastTick: Int = 0

    var body: some View {
        VStack(spacing: 3) {
            caption
            ZStack {
                WaveRulerTicks(value: value, range: range, tick: tick, pointsPerUnit: pointsPerUnit, detents: detents)
                    .mask(LinearGradient(colors: [.clear, .white, .white, .white, .clear], startPoint: .leading, endPoint: .trailing))
                Capsule()
                    .fill(WhisperBrandGradient.accent)
                    .frame(width: 3, height: 22)
            }
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(drag)
            .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? "Adjustment" : label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? tick : -tick
            onEditingChanged?(true)
            value = clamp(value + delta)
            onEditingChanged?(false)
        }
    }

    private var caption: some View {
        HStack {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            Text(format(value))
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                if dragStart == nil {
                    dragStart = value
                    lastTick = tickIndex(value)
                    onEditingChanged?(true)
                }
                guard let start = dragStart else { return }
                var next = clamp(start - Double(gesture.translation.width / pointsPerUnit))
                if let detent = detents.first(where: { abs($0 - next) < tick * 0.75 }) {
                    next = detent
                } else {
                    next = quantize(next)
                }
                let index = tickIndex(next)
                if index != lastTick {
                    if detents.contains(where: { abs($0 - next) < tick / 2 }) { Haptics.rigid() } else { Haptics.selection() }
                    lastTick = index
                }
                if next != value { value = next }
            }
            .onEnded { _ in
                dragStart = nil
                onEditingChanged?(false)
            }
    }

    private func reset() {
        guard value != defaultValue else { return }
        Haptics.rigid()
        onEditingChanged?(true)
        withAnimation(.snappy(duration: 0.25)) { value = defaultValue }
        onEditingChanged?(false)
    }

    private func clamp(_ x: Double) -> Double { min(range.upperBound, max(range.lowerBound, x)) }

    private func quantize(_ x: Double) -> Double {
        let steps = (x / tick).rounded()
        return clamp(steps * tick)
    }

    private func tickIndex(_ x: Double) -> Int { Int((x / tick).rounded()) }
}

/// The ruler face: minor ticks each `tick`, a taller tick every fifth, and the
/// tallest at detents. Drawn only across the visible window.
private struct WaveRulerTicks: View {
    let value: Double
    let range: ClosedRange<Double>
    let tick: Double
    let pointsPerUnit: CGFloat
    let detents: [Double]

    var body: some View {
        Canvas { context, size in
            let center = size.width / 2
            let visible = Double(size.width / pointsPerUnit)
            let first = Int(floor((value - visible / 2) / tick)) - 1
            let last = Int(ceil((value + visible / 2) / tick)) + 1
            guard last >= first else { return }
            for index in first...last {
                let v = Double(index) * tick
                guard v >= range.lowerBound - 1e-6, v <= range.upperBound + 1e-6 else { continue }
                let x = center + CGFloat(v - value) * pointsPerUnit
                let isDetent = detents.contains { abs($0 - v) < tick / 2 }
                let isMajor = isDetent || index % 5 == 0
                let height: CGFloat = isDetent ? 18 : (isMajor ? 12 : 6)
                var path = Path()
                path.move(to: CGPoint(x: x, y: (size.height - height) / 2))
                path.addLine(to: CGPoint(x: x, y: (size.height + height) / 2))
                context.stroke(path, with: .color(.white.opacity(isDetent ? 0.95 : (isMajor ? 0.6 : 0.3))), lineWidth: isDetent ? 2 : 1)
            }
        }
    }
}
