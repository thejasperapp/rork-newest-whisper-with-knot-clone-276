import SwiftUI

/// Lets users send a real sleep / readiness / steps / heart-rate /
/// active-energy snapshot inside a DM. The recipient sees a preview card
/// and can tap "Add to my Whisper" to upsert the row into their own
/// `jasper_*` tables — Whisper's charts then light up in realtime.
///
/// Wire shape mirrors the Whisper↔Whisper contract exactly so the
/// recipient's writer can hand it to Supabase verbatim.
nonisolated enum WhisperHealthShareEmbed {
    static let prefix = "::whisper-healthshare-v1::"

    nonisolated enum Kind: String, Codable, Sendable {
        case sleep
        case readiness
        case steps
        case heartRate = "heartrate"
        case activeEnergy = "active_energy"
        case bioAge = "bioage"

        var title: String {
            switch self {
            case .sleep:        return "Sleep"
            case .readiness:    return "Readiness"
            case .steps:        return "Steps"
            case .heartRate:    return "Heart rate"
            case .activeEnergy: return "Active energy"
            case .bioAge:       return "Biological age"
            }
        }
        var symbol: String {
            switch self {
            case .sleep:        return "moon.zzz.fill"
            case .readiness:    return "bolt.heart.fill"
            case .steps:        return "figure.walk"
            case .heartRate:    return "heart.fill"
            case .activeEnergy: return "flame.fill"
            case .bioAge:       return "waveform.path.ecg"
            }
        }
        var tint: Color {
            switch self {
            case .sleep:        return .indigo
            case .readiness:    return .mint
            case .steps:        return .blue
            case .heartRate:    return .pink
            case .activeEnergy: return .orange
            case .bioAge:       return Color(red: 0.20, green: 0.78, blue: 0.82)
            }
        }
        /// Matches the `scope` segment Whisper uses for deterministic UUIDs.
        var scope: String {
            switch self {
            case .sleep:        return "sleep"
            case .readiness:    return "readiness"
            case .steps:        return "steps"
            case .heartRate:    return "heartrate"
            case .activeEnergy: return "active_energy"
            case .bioAge:       return "bioage"
            }
        }
        static func parse(_ s: String) -> Kind? {
            let l = s.lowercased().trimmingCharacters(in: .whitespaces)
            if l.contains("bio") || l.contains("biological") { return .bioAge }
            if l.contains("sleep") { return .sleep }
            if l.contains("readi") || l.contains("recovery") { return .readiness }
            if l.contains("step") { return .steps }
            if l.contains("heart") || l.contains("hr") || l.contains("bpm") { return .heartRate }
            if l.contains("energy") || l.contains("calor") || l.contains("kcal") || l.contains("active") {
                return .activeEnergy
            }
            return nil
        }
    }

    /// Single payload that carries every variant. Only the fields relevant
    /// to `kind` are populated; the rest stay nil. This keeps the wire
    /// format flat for forward compatibility.
    nonisolated struct Payload: Codable, Sendable, Hashable {
        let kind: String
        let senderUsername: String
        /// ISO8601 UTC, start of the sender's local day.
        let recordedOn: String
        let summary: String

        // Sleep
        let startedAt: String?
        let endedAt: String?
        let durationSeconds: Int?
        let deepSeconds: Int?
        let remSeconds: Int?
        let lightSeconds: Int?
        let awakeSeconds: Int?
        let qualityScore: Int?

        // Readiness
        let readinessScore: Int?
        let sleepScore: Int?
        let recoveryScore: Int?
        let strainScore: Int?

        // Vitals (shared across sleep / readiness / heartrate)
        let restingHR: Int?
        let averageHR: Int?
        let maxHR: Int?
        let minHR: Int?
        let hrvMs: Double?
        let spo2Pct: Double?

        // Steps
        let steps: Int?
        let distanceM: Double?

        // Active energy
        let activeEnergyKcal: Double?
        let basalEnergyKcal: Double?
        let exerciseMinutes: Int?
        let standHours: Int?
        let moveGoalKcal: Int?

        // Biological age (synced from the partner Jasper app). Vars with
        // defaults so every pre-existing memberwise call site still compiles
        // and old payloads decode cleanly.
        var bioAge: Double? = nil
        var chronoAge: Double? = nil
        var deltaYears: Double? = nil
        var confidenceLevel: String? = nil
        var topFactor: String? = nil

        var kindEnum: Kind { Kind(rawValue: kind) ?? .sleep }
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p
    }
}

// MARK: - Inline card

struct WhisperHealthShareInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperHealthShareEmbed.Payload
    let mine: Bool
    /// Recipient action — wired in DMThreadView to call the writer.
    let onSave: () async -> Void

    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle, saving, saved, failed
    }

    var body: some View {
        let kind = payload.kindEnum
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(kind.tint, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title.uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(1.0)
                        .opacity(0.7)
                    Text("@\(payload.senderUsername)'s \(kind.title.lowercased())")
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            nativeVisual

            statsGrid
                .padding(.vertical, 2)

            Text(payload.summary)
                .font(.caption)
                .opacity(0.85)
                .lineLimit(2)

            if !mine, payload.kindEnum != .bioAge {
                Button {
                    guard saveState != .saving, saveState != .saved else { return }
                    saveState = .saving
                    Haptics.tap()
                    Task {
                        await onSave()
                        // Optimistic — DM thread will toast on failure.
                        saveState = .saved
                        Haptics.success()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: saveLabelSymbol)
                            .font(.caption.weight(.bold))
                        Text(saveLabel)
                            .font(.caption.weight(.heavy))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(kind.tint, in: .rect(cornerRadius: 10))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(saveState == .saving || saveState == .saved)
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .foregroundStyle(mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
        .background(
            (mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme)),
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    mine ? Color.clear : WhisperTheme.hairline(colorScheme),
                    lineWidth: 1
                )
        }
    }

    private var saveLabel: String {
        switch saveState {
        case .idle:   return "Add to my Whisper"
        case .saving: return "Saving…"
        case .saved:  return "Added to your charts"
        case .failed: return "Try again"
        }
    }
    private var saveLabelSymbol: String {
        switch saveState {
        case .idle:   return "chart.line.uptrend.xyaxis"
        case .saving: return "arrow.triangle.2.circlepath"
        case .saved:  return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    @ViewBuilder
    private var statsGrid: some View {
        let stats = primaryStats()
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.value)
                        .font(.title3.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(s.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .opacity(0.65)
                }
                if s.label != stats.last?.label {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Jasper's native render treatments — the recovery ring, the sleep
    /// hypnogram, and the vitality blob — so shared metrics look exactly
    /// like they do inside Jasper.
    @ViewBuilder
    private var nativeVisual: some View {
        switch payload.kindEnum {
        case .readiness:
            if let score = payload.readinessScore {
                HStack(spacing: 12) {
                    JasperRecoveryRing(score: score, size: 80)
                    JasperReadinessBars(sleep: payload.sleepScore,
                                        recovery: payload.recoveryScore,
                                        strain: payload.strainScore)
                }
                .padding(.vertical, 2)
            }
        case .sleep:
            if payload.deepSeconds != nil || payload.remSeconds != nil
                || payload.lightSeconds != nil || payload.awakeSeconds != nil {
                JasperHypnogram(startedAt: jasperConnectDate(payload.startedAt),
                                endedAt: jasperConnectDate(payload.endedAt),
                                awakeSeconds: payload.awakeSeconds,
                                remSeconds: payload.remSeconds,
                                coreSeconds: payload.lightSeconds,
                                deepSeconds: payload.deepSeconds,
                                qualityScore: payload.qualityScore,
                                compact: true)
                    .padding(.vertical, 2)
            }
        case .bioAge:
            HStack {
                Spacer(minLength: 0)
                ZStack {
                    JasperVitalityBlob(deltaYears: payload.deltaYears, size: 86, compact: true)
                    Text(payload.bioAge.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
                .frame(height: 100)
                Spacer(minLength: 0)
            }
        default:
            EmptyView()
        }
    }

    private struct Stat { let value: String; let label: String }

    private func primaryStats() -> [Stat] {
        switch payload.kindEnum {
        case .sleep:
            let dur = payload.durationSeconds ?? 0
            let h = dur / 3600
            let m = (dur % 3600) / 60
            return [
                Stat(value: "\(h)h \(m)m", label: "Total"),
                Stat(value: "\(payload.qualityScore ?? 0)", label: "Quality"),
                Stat(value: payload.restingHR.map { "\($0)" } ?? "—", label: "RHR")
            ]
        case .readiness:
            return [
                Stat(value: "\(payload.readinessScore ?? 0)", label: "Score"),
                Stat(value: "\(payload.recoveryScore ?? 0)", label: "Recovery"),
                Stat(value: "\(payload.sleepScore ?? 0)", label: "Sleep")
            ]
        case .steps:
            let dist = payload.distanceM.map { String(format: "%.1f km", $0 / 1000) } ?? "—"
            return [
                Stat(value: formatted(Double(payload.steps ?? 0)), label: "Steps"),
                Stat(value: dist, label: "Distance")
            ]
        case .heartRate:
            return [
                Stat(value: payload.restingHR.map { "\($0)" } ?? "—", label: "Resting"),
                Stat(value: payload.averageHR.map { "\($0)" } ?? "—", label: "Avg"),
                Stat(value: payload.maxHR.map { "\($0)" } ?? "—", label: "Max")
            ]
        case .activeEnergy:
            return [
                Stat(value: "\(Int((payload.activeEnergyKcal ?? 0).rounded()))", label: "Active kcal"),
                Stat(value: payload.exerciseMinutes.map { "\($0)m" } ?? "—", label: "Exercise"),
                Stat(value: payload.standHours.map { "\($0)" } ?? "—", label: "Stand")
            ]
        case .bioAge:
            let delta = payload.deltaYears.map { d -> String in
                let mag = abs(d)
                guard mag >= 0.05 else { return "on par" }
                return String(format: "%@%.1fy", d < 0 ? "−" : "+", mag)
            } ?? "—"
            return [
                Stat(value: payload.bioAge.map { String(format: "%.1f", $0) } ?? "—", label: "Bio age"),
                Stat(value: payload.chronoAge.map { "\(Int($0.rounded()))" } ?? "—", label: "Real age"),
                Stat(value: delta, label: "Delta")
            ]
        }
    }

    private func formatted(_ v: Double) -> String {
        if v >= 10_000 { return String(format: "%.1fk", v / 1000) }
        if v >= 1_000 { return String(format: "%.2fk", v / 1000) }
        return "\(Int(v))"
    }
}
