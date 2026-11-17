import Foundation

/// Full decoded response from the shared Jasper code interpreter
/// (`POST /interpret`). The engine — router → ops/Python sandbox → agent
/// loop → charts — is ENTIRELY server-side and app-agnostic. Whisper never
/// reproduces any of it; we just decode this trace and render it honestly:
/// the executed code, the real output, charts, and the per-phase log.
///
/// Every field is optional because the router may decide computation doesn't
/// help (`engine: "skip"`), in which case we show no chip and fall through to
/// the plain chat reply.
nonisolated struct WhisperInterpretResult: Decodable, Sendable, Hashable {
    let ok: Bool
    let authored: String?     // python | model | fallback | skip
    let engine: String?       // python | ops | skip
    let strategy: String?     // correlation | trend | projection | …
    let intent: String?
    let code: String?
    let output: String?
    let rounds: [Round]?
    let charts: [ChartSpec]?
    let artifacts: [Artifact]?
    let trace: [TracePhase]?
    let ms: Int?

    /// One self-directed agent round (the model digging deeper, up to 3).
    nonisolated struct Round: Decodable, Sendable, Hashable {
        let intent: String?
        let code: String?
        let output: String?
    }

    /// A native chart spec built from the SAME real numbers the code returned.
    nonisolated struct ChartSpec: Decodable, Sendable, Hashable, Identifiable {
        let kind: String?     // line | scatter | bar
        let title: String?
        let caption: String?
        let xLabel: String?
        let yLabel: String?
        let series: [Series]?

        var id: String { (title ?? "") + (kind ?? "") + (caption ?? "") }

        nonisolated struct Series: Decodable, Sendable, Hashable, Identifiable {
            let name: String?
            let points: [Point]?
            var id: String { name ?? "series" }
        }

        nonisolated struct Point: Decodable, Sendable, Hashable {
            let x: Double
            let y: Double
            let label: String?

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.x = Self.number(c, .x) ?? 0
                self.y = Self.number(c, .y) ?? 0
                self.label = try? c.decodeIfPresent(String.self, forKey: .label)
            }

            private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
                if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
                if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
                if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
                return nil
            }
            enum CodingKeys: String, CodingKey { case x, y, label }
        }
    }

    /// A ready-to-display artifact (e.g. a Matplotlib PNG) from a Python run.
    nonisolated struct Artifact: Decodable, Sendable, Hashable, Identifiable {
        let id: String?
        let kind: String?
        let mimeType: String?
        let title: String?
        let base64: String?

        /// Stable identity for ForEach even when the server omits `id`.
        var stableID: String { id ?? ((title ?? "artifact") + String((base64 ?? "").prefix(24))) }
    }

    /// One real phase of the pipeline (router, author, execute, …) with timing.
    nonisolated struct TracePhase: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        let label: String
        let detail: String?
        let ms: Int?
    }

    // MARK: - Derived

    /// True when the router decided computation won't help — render no chip.
    var isSkip: Bool {
        let e = engine?.lowercased()
        let a = authored?.lowercased()
        return e == "skip" || a == "skip" || (e == nil && a == nil && (output?.isEmpty ?? true))
    }

    /// True when the executed engine was real Python (vs the deterministic
    /// stats op-pipeline). Controls whether we show the "Python" code block.
    var isPython: Bool { engine?.lowercased() == "python" }

    /// The executed source to display — the latest round's code wins, since
    /// the agent loop builds on each prior step.
    var displayCode: String? {
        if let c = rounds?.last?.code, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return c
        }
        if let c = code, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return c }
        return nil
    }

    /// The chip label shown under the Jasper bubble. Falls back gracefully so a
    /// non-skip result without an explicit intent still gets a sensible label.
    var chipLabel: String {
        if let intent, !intent.isEmpty { return intent }
        if let strategy, !strategy.isEmpty, strategy.lowercased() != "auto" {
            return "Ran a \(strategy) analysis on your data"
        }
        return "Analyzed your data"
    }

    /// Sheet header — distinguishes the real Python sandbox from the
    /// deterministic stats engine, appending the strategy unless it's `auto`.
    var sheetHeader: String {
        let base = isPython ? "Real Python" : "Stats engine"
        if let strategy, !strategy.isEmpty, strategy.lowercased() != "auto" {
            return "\(base) · \(strategy)"
        }
        return base
    }

    /// True only when the server actually RAN a computation (real Python or the
    /// deterministic stats op-pipeline) and produced something real. This is the
    /// gate for the thinking chip — so a chip appears only when there's genuine
    /// code/output behind it, never on a greeting, lookup, or skipped turn.
    var didCompute: Bool {
        guard !isSkip else { return false }
        let e = engine?.lowercased()
        guard e == "python" || e == "ops" else { return false }
        return hasDetail
    }

    /// Builds a native chart card from the REAL numbers the interpreter returned
    /// (its `charts[]`, computed server-side from the user's actual series),
    /// mapped into the shared block-chart shape so it renders identically to a
    /// brain-authored chart — but data-accurate. Returns nil when no chart with
    /// real points exists. Prefer this over the model's fenced ```chart block so
    /// the visible chart always reflects computed data, never estimated figures.
    var realDataChart: WhisperEmberBlocks.Chart? {
        guard let spec = charts?.first(where: { spec in
            (spec.series ?? []).contains { !($0.points?.isEmpty ?? true) }
        }) else { return nil }

        let type: String
        switch (spec.kind ?? "line").lowercased() {
        case "scatter": type = "point"
        case "bar":     type = "bar"
        default:        type = "line"
        }

        let series = (spec.series ?? []).compactMap { s -> WhisperEmberBlocks.Chart.Series? in
            let points = (s.points ?? []).map { p in
                WhisperEmberBlocks.Chart.Point(
                    x: p.label ?? Self.axisLabel(p.x),
                    y: p.y
                )
            }
            guard !points.isEmpty else { return nil }
            return WhisperEmberBlocks.Chart.Series(name: s.name, data: points)
        }
        guard !series.isEmpty else { return nil }

        // Single-series charts render cleaner via `data`; multi-series via `series`.
        if series.count == 1 {
            return WhisperEmberBlocks.Chart(
                type: type,
                title: spec.title ?? spec.yLabel,
                unit: spec.yLabel ?? spec.caption,
                goal: nil,
                data: series[0].data,
                series: nil
            )
        }
        return WhisperEmberBlocks.Chart(
            type: type,
            title: spec.title ?? spec.yLabel,
            unit: spec.yLabel ?? spec.caption,
            goal: nil,
            data: nil,
            series: series
        )
    }

    private static func axisLabel(_ x: Double) -> String {
        x.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(x)) : String(format: "%g", x)
    }

    /// Whether anything meaningful exists to show in the detail sheet.
    var hasDetail: Bool {
        (displayCode != nil) || !(output?.isEmpty ?? true)
            || !(charts?.isEmpty ?? true) || !(artifacts?.isEmpty ?? true)
            || !(rounds?.isEmpty ?? true)
    }

    /// The interpreter context block spliced into `/ember/chat` so Jasper cites
    /// the REAL computed numbers verbatim instead of estimating. Built exactly
    /// like Whisper does. Returns nil when there's nothing real to cite.
    var emberContextBlock: String? {
        guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        var lines: [String] = []
        lines.append("=== JASPER CODE INTERPRETER (real computation that just ran on the user's data) ===")
        lines.append("Goal: \(intent ?? "Analyze the user's data")")
        if let rounds, rounds.count > 1 {
            lines.append("Jasper ran \(rounds.count) self-directed analysis steps, each building on the last.")
        }
        lines.append("Output:")
        lines.append(output)
        lines.append("These numbers are REAL — computed server-side from the user's actual series. Cite them verbatim; never invent other figures.")
        return lines.joined(separator: "\n")
    }
}

extension WhisperEmberBrainService {
    private nonisolated struct InterpretFullRequest: Encodable {
        let question: String
        let dataset: Dataset
    }

    /// Runs the full interpreter pipeline and returns the entire trace so the
    /// chat layer can render the thinking-chip UI (code + output + charts +
    /// artifacts). Returns nil on ANY failure (non-200, `ok:false`, decode,
    /// network) — the interpreter is an enhancement, never a hard dependency,
    /// so callers fall through silently to a plain chat reply.
    func interpretFull(question: String, dataset: Dataset, timeout: TimeInterval = 35) async -> WhisperInterpretResult? {
        guard let url = URL(string: "\(Self.baseURL)/interpret") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // A Python round plus sandbox spin-up can take a few seconds.
        request.timeoutInterval = timeout
        guard let body = try? JSONEncoder().encode(
            InterpretFullRequest(question: question, dataset: dataset)
        ) else { return nil }
        request.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return nil
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
        guard let decoded = try? JSONDecoder().decode(WhisperInterpretResult.self, from: data),
              decoded.ok else { return nil }
        return decoded
    }
}
