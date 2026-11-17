import SwiftUI

// MARK: - Hex parsing

/// RGB triple parsed from a "#RRGGBB" hex string — kept as raw components so
/// the vitality palette can lerp per-channel exactly like Jasper's spec.
struct JasperRGB {
    let r: Double
    let g: Double
    let b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init?(hex raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, s.allSatisfy(\.isHexDigit),
              let v = UInt32(s, radix: 16) else { return nil }
        self.r = Double((v >> 16) & 0xFF) / 255
        self.g = Double((v >> 8) & 0xFF) / 255
        self.b = Double(v & 0xFF) / 255
    }

    func lerp(_ other: JasperRGB, _ f: Double) -> JasperRGB {
        let clamped = min(1, max(0, f))
        return JasperRGB(r: r + (other.r - r) * clamped,
                         g: g + (other.g - g) * clamped,
                         b: b + (other.b - b) * clamped)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

extension Color {
    /// "#RRGGBB" (leading # optional). Nil for anything else.
    init?(jasperHex raw: String) {
        guard let rgb = JasperRGB(hex: raw) else { return nil }
        self = rgb.color
    }
}

// MARK: - One look spec

/// A thin, forgiving reader over one of Jasper's `look` render specs (the
/// JSON that now rides along with /v1/bioage, /v1/readiness, /v1/sleep, and
/// /v1/shared_charts reads). Colors and thresholds are read at RUNTIME so a
/// Jasper design tweak restyles Whisper with zero code changes; every
/// accessor is optional and renderers fall back to the published defaults.
struct JasperLook {
    let raw: [String: Any]

    func string(_ key: String) -> String? { raw[key] as? String }
    func strings(_ key: String) -> [String]? { raw[key] as? [String] }
    func dict(_ key: String) -> [String: Any]? { raw[key] as? [String: Any] }
    func look(_ key: String) -> JasperLook? { dict(key).map { JasperLook(raw: $0) } }

    func double(_ key: String) -> Double? {
        if let d = raw[key] as? Double { return d }
        if let i = raw[key] as? Int { return Double(i) }
        if let n = raw[key] as? NSNumber { return n.doubleValue }
        return nil
    }

    /// "#RRGGBB" string at a structured key.
    func color(_ key: String) -> Color? {
        (raw[key] as? String).flatMap { Color(jasperHex: $0) }
    }

    /// Every #RRGGBB inside a prose field, in order — several spec fields
    /// describe their colors in sentences ("score ≥ 75 → #5CDBB8 …").
    func proseColors(_ key: String) -> [Color] {
        Self.hexColors(in: string(key) ?? "")
    }

    /// Every plain number inside a prose field with hex tokens stripped
    /// first (so "#5CDBB8" never leaks digits into thresholds).
    func proseNumbers(_ key: String) -> [Double] {
        Self.numbers(in: string(key) ?? "")
    }

    static func hexColors(in text: String) -> [Color] {
        var out: [Color] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i] == "#", i + 6 < chars.count + 1, i + 7 <= chars.count {
                let candidate = String(chars[(i + 1)..<(i + 7)])
                if candidate.allSatisfy(\.isHexDigit), let color = Color(jasperHex: candidate) {
                    out.append(color)
                    i += 7
                    continue
                }
            }
            i += 1
        }
        return out
    }

    static func numbers(in text: String) -> [Double] {
        // Strip #RRGGBB tokens first so hex digits never pollute thresholds.
        var cleaned = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i] == "#", i + 7 <= chars.count,
               String(chars[(i + 1)..<(i + 7)]).allSatisfy(\.isHexDigit) {
                i += 7
                continue
            }
            cleaned.append(chars[i])
            i += 1
        }
        var out: [Double] = []
        var current = ""
        for ch in cleaned {
            if ch.isNumber || (ch == "." && !current.isEmpty && !current.contains(".")) {
                current.append(ch)
            } else {
                if !current.isEmpty, let v = Double(current) { out.append(v) }
                current = ""
            }
        }
        if !current.isEmpty, let v = Double(current) { out.append(v) }
        return out
    }
}

// MARK: - Store

/// Live render specs from Jasper. Two feeds keep it fresh with zero extra
/// contract: (1) every Connect read of a look-carrying resource ingests the
/// `look` object that rides in the envelope; (2) the public catalog's `looks`
/// object refreshes at most daily. Last-seen specs persist so native looks
/// render correctly offline and before the first fetch.
@Observable
final class JasperLookStore {
    static let shared = JasperLookStore()

    /// look kind ("bioage" / "readiness" / "sleep" / "charts" / "brand") → spec.
    private(set) var looks: [String: JasperLook] = [:]

    private var rawJSON: [String: String] = [:]
    private var catalogFetchedAt: Date?
    private var refreshing = false
    private static let defaultsKey = "jasper_looks_v1"

    /// resource name → look kind, per the catalog's `resources[].look`.
    private static let resourceKinds: [String: String] = [
        "bioage": "bioage",
        "readiness": "readiness",
        "sleep": "sleep",
        "shared_charts": "charts",
    ]

    private init() {
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) else { return }
        for (kind, value) in saved {
            guard let json = value as? String,
                  let data = json.data(using: .utf8),
                  let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            rawJSON[kind] = json
            looks[kind] = JasperLook(raw: dict)
        }
    }

    func look(_ kind: String) -> JasperLook? { looks[kind] }

    /// Rides along every Connect read — pulls the top-level `look` object out
    /// of a data envelope. Cheap: skipped entirely unless the resource ships
    /// looks, and re-parsing is deduped by comparing canonical JSON.
    func ingest(resource: String, envelope: Data) {
        guard let kind = Self.resourceKinds[resource] else { return }
        guard let body = (try? JSONSerialization.jsonObject(with: envelope)) as? [String: Any],
              let dict = body["look"] as? [String: Any], !dict.isEmpty else { return }
        store(kind: kind, dict: dict)
    }

    /// The one-call dashboard (`GET /v1/dashboard`) bundles EVERY look in a
    /// top-level `looks` object (same shape as the catalog's) — ingest them
    /// all so native renders stay current without per-resource reads.
    func ingest(looksBundle envelope: Data) {
        guard let body = (try? JSONSerialization.jsonObject(with: envelope)) as? [String: Any],
              let all = body["looks"] as? [String: Any], !all.isEmpty else { return }
        for (kind, value) in all {
            if let dict = value as? [String: Any] { store(kind: kind, dict: dict) }
        }
    }

    /// The catalog is public — refresh its `looks` at most daily so Jasper
    /// design tweaks flow through even before the next data read.
    func refreshIfStale(maxAge: TimeInterval = 86_400) async {
        if refreshing { return }
        if let last = catalogFetchedAt, Date().timeIntervalSince(last) < maxAge { return }
        refreshing = true
        defer { refreshing = false }
        var request = URLRequest(url: JasperConnectConfig.apiBase.appendingPathComponent("v1/catalog"))
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let all = body["looks"] as? [String: Any], !all.isEmpty else { return }
            for (kind, value) in all {
                if let dict = value as? [String: Any] { store(kind: kind, dict: dict) }
            }
            catalogFetchedAt = Date()
            print("[JasperLooks] catalog looks refreshed: \(all.keys.sorted().joined(separator: ", "))")
        } catch {
            print("[JasperLooks] catalog refresh failed: \(error.localizedDescription)")
        }
    }

    private func store(kind: String, dict: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        guard rawJSON[kind] != json else { return }
        rawJSON[kind] = json
        looks[kind] = JasperLook(raw: dict)
        UserDefaults.standard.set(rawJSON, forKey: Self.defaultsKey)
        print("[JasperLooks] \(kind) look updated")
    }
}

// MARK: - Vitality palette math (bioage look)

/// Jasper's vitality math: t = (clamp(delta_years, −10, 10) + 10) / 20 —
/// 0 = 10y younger (green), 0.5 = on par (teal), 1 = 10y older (red).
/// Stops and accent thresholds prefer the live `look` spec.
enum JasperVitalityPalette {
    static let defaultYounger = ["#4DF28C", "#1ACC80", "#0D8C73"]
    static let defaultOnPar = ["#33D9CC", "#26A6D9", "#1A73B3"]
    static let defaultOlder = ["#FF734D", "#F28C33", "#CC3340"]

    static func vitalityT(deltaYears: Double?) -> Double {
        guard let deltaYears, deltaYears.isFinite else { return 0.5 }
        return (min(10, max(-10, deltaYears)) + 10) / 20
    }

    /// The 3 gradient stops at t, lerped younger→on_par→older per the
    /// published palette rule.
    static func stops(t: Double) -> [Color] {
        let look = JasperLookStore.shared.look("bioage")?.look("palette_stops")
        func band(_ key: String, _ fallback: [String]) -> [JasperRGB] {
            let hexes = look?.strings(key) ?? fallback
            let rgbs = hexes.compactMap { JasperRGB(hex: $0) }
            if rgbs.count == 3 { return rgbs }
            return fallback.compactMap { JasperRGB(hex: $0) }
        }
        let younger = band("younger", defaultYounger)
        let onPar = band("on_par", defaultOnPar)
        let older = band("older", defaultOlder)
        let clamped = min(1, max(0, t))
        let mixed: [JasperRGB]
        if clamped < 0.5 {
            mixed = zip(younger, onPar).map { $0.lerp($1, clamped / 0.5) }
        } else {
            mixed = zip(onPar, older).map { $0.lerp($1, (clamped - 0.5) / 0.5) }
        }
        return mixed.map(\.color)
    }

    /// UI accent by t — hexes and thresholds parsed from the live spec's
    /// accent rule ("< 0.5 → #40D98C · < 0.62 → #33C7D1 · else #FF8052").
    static func accent(deltaYears: Double?) -> Color {
        let t = vitalityT(deltaYears: deltaYears)
        let look = JasperLookStore.shared.look("bioage")
        let hexes = look?.proseColors("accent") ?? []
        let thresholds = (look?.proseNumbers("accent") ?? []).filter { $0 > 0 && $0 < 1 }
        let younger = hexes.count == 3 ? hexes[0] : (Color(jasperHex: "#40D98C") ?? .green)
        let onPar = hexes.count == 3 ? hexes[1] : (Color(jasperHex: "#33C7D1") ?? .teal)
        let older = hexes.count == 3 ? hexes[2] : (Color(jasperHex: "#FF8052") ?? .orange)
        let low = thresholds.first ?? 0.5
        let mid = thresholds.count > 1 ? thresholds[1] : 0.62
        if t < low { return younger }
        if t < mid { return onPar }
        return older
    }
}
