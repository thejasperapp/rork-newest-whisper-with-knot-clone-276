import SwiftUI

/// Resolves the "Auto" personality — Jasper picks today's ghost from the
/// user's live readiness score, with an honest reason line (never a silent
/// guess). The resolution is cached so palette lookups stay synchronous;
/// `refresh()` re-reads readiness whenever the chat or mood selector opens
/// (15-minute staleness window, forceable).
///
/// Mapping (honest and simple):
/// - readiness ≥ 75 → Drill Sergeant (fresh — push)
/// - 50…74        → The Original (steady day)
/// - < 50         → Angel (recovery first)
/// - no data      → The Original, and the reason says so
enum WhisperEmberAutoMood {
    private static let modeKey = "whisper_ember_auto_resolved_mode"
    private static let reasonKey = "whisper_ember_auto_reason"
    private static let scoreKey = "whisper_ember_auto_score"
    private static let stampKey = "whisper_ember_auto_stamp"

    /// The concrete ghost Auto currently resolves to. Never returns `.auto`.
    static var resolved: WhisperEmberCoachMode {
        guard let raw = AccountStorage.string(forKey: modeKey),
              let mode = WhisperEmberCoachMode(rawValue: raw),
              mode != .auto else { return .regular }
        return mode
    }

    /// The honest one-line reason behind the current resolution.
    static var reason: String {
        AccountStorage.string(forKey: reasonKey)
            ?? "No readiness synced yet, so the classic Jasper carries today."
    }

    /// Latest readiness score used for the resolution, if any.
    static var latestScore: Int? {
        AccountStorage.string(forKey: scoreKey).flatMap { Int($0) }
    }

    /// Re-resolves Auto from the newest readiness score. Cheap to call —
    /// skips the network inside the staleness window unless forced. Posts
    /// `whisperEmberModeChanged` when the resolved ghost actually changes
    /// while Auto is the saved selection, so every surface retints live.
    @MainActor
    static func refresh(force: Bool = false) async {
        let generation = AccountStorage.generation
        guard !Task.isCancelled else { return }
        let now = Date().timeIntervalSince1970
        if !force,
           let stamp = AccountStorage.string(forKey: stampKey),
           let last = Double(stamp),
           now - last < 900 {
            return
        }
        var score: Int?
        if let uid = await WhisperWhisperLinkService.shared.resolvedWhisperUID(), !uid.isEmpty {
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            let row = await WhisperWhisperDataService.shared.fetchLatestReadiness(userID: uid)
            if let value = row?.score { score = Int(value.rounded()) }
        }

        guard generation == AccountStorage.generation, !Task.isCancelled else { return }
        AccountStorage.set(String(now), forKey: stampKey)
        let previous = resolved
        let concrete: WhisperEmberCoachMode
        let line: String
        if let score {
            AccountStorage.set(String(score), forKey: scoreKey)
            if score >= 75 {
                concrete = .drillSergeant
                line = "Readiness \(score) — fresh and loaded, so the Drill Sergeant pushes today."
            } else if score >= 50 {
                concrete = .regular
                line = "Readiness \(score) — a steady day, so the classic Jasper carries it."
            } else {
                concrete = .guardian
                line = "Readiness \(score) — recovery comes first, so Angel takes today."
            }
        } else {
            concrete = .regular
            line = "No readiness synced yet, so the classic Jasper carries today."
        }

        AccountStorage.set(concrete.rawValue, forKey: modeKey)
        AccountStorage.set(line, forKey: reasonKey)

        if previous != concrete, WhisperEmberCoachMode.load() == .auto {
            NotificationCenter.default.post(name: .whisperEmberModeChanged, object: nil)
        }
    }
}
