import SwiftUI
import Charts

/// The visible magic: a small contextual chip under an Jasper bubble that
/// represents the REAL analysis the server-side interpreter just ran. Tapping
/// it opens a sheet with the executed code, the real output, and any charts —
/// because that transparency (never faking a number) is the whole point.
struct WhisperEmberThinkingChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let result: WhisperInterpretResult
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: result.isPython ? "terminal.fill" : "function")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.orange)
                Text(result.chipLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(WhisperTheme.card(colorScheme), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The animated "Thinking" chip shown under the in-progress Jasper bubble while
/// the interpreter pipeline runs. When the live trace is available it animates
/// through the real per-phase labels (router → author → execute → …) for a
/// genuine "it's actually working" feel.
struct WhisperEmberLiveThinkingChip: View {
    @Environment(\.colorScheme) private var colorScheme
    /// Optional contextual label once the interpreter resolves (swaps the
    /// generic "Thinking" for the real intent before the chat reply lands).
    let resolvedLabel: String?

    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            if resolvedLabel == nil {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Color.orange)
            } else {
                Image(systemName: "function")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.orange)
            }
            Text(resolvedLabel ?? "Thinking")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        }
        .opacity(pulse ? 1 : 0.6)
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
    }
}

/// Detail sheet revealing the REAL code + output + charts behind a chip. Built
/// to honestly represent the pipeline: Python source (only when Python ran),
/// each agent round labelled, native charts from the real numbers, and any
/// PNG artifacts inline.
struct WhisperEmberInterpretSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let result: WhisperInterpretResult

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WhisperJasperIntelligencePill(compact: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                    header
                    if let trace = result.trace, !trace.isEmpty {
                        traceSection(trace)
                    }
                    roundsSection
                    if let charts = result.charts, !charts.isEmpty {
                        ForEach(charts) { chart in
                            chartCard(chart)
                        }
                    }
                    if let artifacts = result.artifacts, !artifacts.isEmpty {
                        ForEach(artifacts) { artifact in
                            artifactCard(artifact)
                        }
                    }
                    footnote
                }
                .padding(18)
            }
            .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
            .navigationTitle("How Knot knows")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: result.isPython ? "terminal.fill" : "function")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.orange, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(result.sheetHeader)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Computed live on your real data")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer(minLength: 0)
            if let ms = result.ms, ms > 0 {
                Text("\(ms) ms")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
            }
        }
    }

    // MARK: - Trace

    private func traceSection(_ trace: [WhisperInterpretResult.TracePhase]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Pipeline")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(trace.enumerated()), id: \.element.id) { idx, phase in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 7, height: 7)
                            if idx < trace.count - 1 {
                                Rectangle()
                                    .fill(WhisperTheme.hairline(colorScheme))
                                    .frame(width: 1.5)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(height: phase.detail == nil ? 22 : 40)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(phase.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Spacer(minLength: 0)
                                if let ms = phase.ms {
                                    Text("\(ms)ms")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                            }
                            if let detail = phase.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        }
    }

    // MARK: - Rounds (code + output)

    @ViewBuilder
    private var roundsSection: some View {
        let rounds = result.rounds ?? []
        if rounds.count > 1 {
            ForEach(Array(rounds.enumerated()), id: \.offset) { idx, round in
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Step \(idx + 1) — \(round.intent ?? "Analysis")")
                    if result.isPython, let code = round.code,
                       !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        codeBlock(code)
                    }
                    if let out = round.output, !out.isEmpty {
                        outputBlock(out)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let intent = result.intent, !intent.isEmpty {
                    sectionLabel(intent)
                }
                if result.isPython, let code = result.displayCode {
                    codeBlock(code)
                }
                if let out = result.output, !out.isEmpty {
                    Text("→ Output")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.6)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    outputBlock(out)
                }
            }
        }
    }

    private func codeBlock(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 9, weight: .bold))
                Text("Python")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.6)
            }
            .foregroundStyle(Color.orange)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(
                (colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.05)),
                in: .rect(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
        }
    }

    private func outputBlock(_ output: String) -> some View {
        Text(output)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
    }

    // MARK: - Charts

    private func chartCard(_ chart: WhisperInterpretResult.ChartSpec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = chart.title, !title.isEmpty {
                sectionLabel(title)
            }
            Chart {
                ForEach(Array((chart.series ?? []).enumerated()), id: \.offset) { idx, series in
                    let tint = Self.palette[idx % Self.palette.count]
                    ForEach(Array((series.points ?? []).enumerated()), id: \.offset) { _, p in
                        chartMark(kind: chart.kind ?? "line", point: p, tint: tint)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel().font(.caption2)
                }
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption2) }
            }
            .frame(height: 160)
            if let caption = chart.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    @ChartContentBuilder
    private func chartMark(
        kind: String,
        point: WhisperInterpretResult.ChartSpec.Point,
        tint: Color
    ) -> some ChartContent {
        switch kind.lowercased() {
        case "scatter":
            PointMark(x: .value("x", point.x), y: .value("y", point.y))
                .foregroundStyle(tint)
                .symbolSize(40)
        case "bar":
            BarMark(
                x: .value("x", point.label ?? String(format: "%g", point.x)),
                y: .value("y", point.y)
            )
            .foregroundStyle(tint.gradient)
            .cornerRadius(4)
        default: // line
            LineMark(x: .value("x", point.x), y: .value("y", point.y))
                .foregroundStyle(tint)
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("x", point.x), y: .value("y", point.y))
                .foregroundStyle(tint)
                .symbolSize(20)
        }
    }

    // MARK: - Artifacts

    @ViewBuilder
    private func artifactCard(_ artifact: WhisperInterpretResult.Artifact) -> some View {
        if let base64 = artifact.base64,
           let data = Data(base64Encoded: base64),
           let uiImage = UIImage(data: data) {
            VStack(alignment: .leading, spacing: 8) {
                if let title = artifact.title, !title.isEmpty {
                    sectionLabel(title)
                }
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 12))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
        }
    }

    // MARK: - Footnote

    private var footnote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(Color.orange)
            Text("These are the exact numbers Knot used — computed on your data, never invented.")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.top, 2)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.heavy))
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private static let palette: [Color] = [.orange, .blue, .green, .purple, .pink]
}
