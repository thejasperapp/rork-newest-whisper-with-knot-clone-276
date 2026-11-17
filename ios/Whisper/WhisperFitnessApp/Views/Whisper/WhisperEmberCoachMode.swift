import SwiftUI

/// User-selectable coaching tone for Whisper's full-screen Jasper assistant.
/// Restyled for Whisper's black & white aesthetic: the default "Original" mode
/// is monochrome (greyscale ghost), while the three character modes keep their
/// signature signal colours so the personality reads at a glance.
enum WhisperEmberCoachMode: String, CaseIterable, Identifiable {
    case auto
    case regular
    case guardian
    case drillSergeant = "drill_sergeant"
    case scientist

    var id: String { rawValue }

    /// The concrete ghost this selection renders as. `.auto` resolves to a
    /// real personality via the cached readiness read (never `.auto` back).
    var resolved: WhisperEmberCoachMode {
        self == .auto ? WhisperEmberAutoMood.resolved : self
    }

    var isAuto: Bool { self == .auto }

    static let storageKey = "whisper_ember_coach_mode"

    static func load() -> WhisperEmberCoachMode {
        guard let raw = AccountStorage.string(forKey: storageKey) else { return .regular }
        switch raw {
        case "comforting", "comfort": return .guardian
        case "angry", "drill", "drillSergeant": return .drillSergeant
        default: return WhisperEmberCoachMode(rawValue: raw) ?? .regular
        }
    }

    func save() {
        AccountStorage.set(rawValue, forKey: Self.storageKey)
        // Every Jasper surface (chat, meeting pill, widgets) re-reads the
        // saved mode when this fires — personality switches apply app-wide.
        NotificationCenter.default.post(name: .whisperEmberModeChanged, object: nil)
    }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .regular: return "The Original"
        case .guardian: return "Angel"
        case .drillSergeant: return "Drill Sergeant"
        case .scientist: return "Scientist"
        }
    }

    var shortTitle: String {
        switch self {
        case .auto: return "Auto"
        case .regular: return "Original"
        case .guardian: return "Angel"
        case .drillSergeant: return "Drill"
        case .scientist: return "Science"
        }
    }

    var icon: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .regular: return "sparkles"
        case .guardian: return "shield.lefthalf.filled"
        case .drillSergeant: return "flame.fill"
        case .scientist: return "atom"
        }
    }

    var selectorTagline: String {
        switch self {
        case .auto: return "Jasper picks from today's readiness"
        case .regular: return "Balanced everyday coach"
        case .guardian: return "Protective, recovery-first support"
        case .drillSergeant: return "Tough-love accountability"
        case .scientist: return "Deep data + physiology lens"
        }
    }

    /// Longer copy for the full-screen personality stage (native Jasper
    /// picker) — reads under the big title while the ghost glows centre-stage.
    var selectorDescription: String {
        switch self {
        case .auto:
            return "Jasper reads today's readiness and picks the right coach for you. " + WhisperEmberAutoMood.reason
        case .regular:
            return "The everyday Jasper — balanced, clever, and honest with your numbers. Warm when you need it, direct when it matters."
        case .guardian:
            return "Protective and calm. Angel lowers the pressure, validates your effort, and always leads with recovery-first advice."
        case .drillSergeant:
            return "Zero excuses. The Drill Sergeant brings tough-love intensity and holds you accountable to every single rep."
        case .scientist:
            return "Data-first explanations. The Scientist reasons through the physiology, trends, and mechanisms behind every recommendation."
        }
    }

    // MARK: - Palette
    //
    // "Regular" stays monochrome to honour Whisper's black & white look; the
    // character modes carry a single signal hue used only on the living ghost
    // and its glow (never as a page background).

    var accent: Color {
        switch self {
        case .auto: return resolved.accent
        case .regular: return Color(red: 0.76, green: 0.99, blue: 0.90)   // THE signature mint #C2FCE6 (jasper-plan.md definitive)
        case .guardian: return Color(red: 1.00, green: 0.78, blue: 0.26)  // #FFC742
        case .drillSergeant: return Color(red: 0.96, green: 0.20, blue: 0.16)  // #F53329
        case .scientist: return Color(red: 0.58, green: 0.38, blue: 1.00)  // #9461FF
        }
    }

    var deepAccent: Color {
        switch self {
        case .auto: return resolved.deepAccent
        case .regular: return Color(red: 0.58, green: 0.82, blue: 0.72)   // shadow edge #94D1B8 (jasper-plan.md definitive)
        case .guardian: return Color(red: 0.86, green: 0.55, blue: 0.05)  // #DB8C0D
        case .drillSergeant: return Color(red: 0.64, green: 0.05, blue: 0.04)  // #A30D0A
        case .scientist: return Color(red: 0.32, green: 0.17, blue: 0.72)  // #522BB8
        }
    }

    var softAccent: Color {
        switch self {
        case .auto: return resolved.softAccent
        case .regular: return Color(red: 0.93, green: 1.00, blue: 0.96)   // top sheen #EDFFF5 (jasper-plan.md definitive)
        case .guardian: return Color(red: 1.00, green: 0.92, blue: 0.56)  // #FFEB8F
        case .drillSergeant: return Color(red: 1.00, green: 0.52, blue: 0.42)  // #FF856B
        case .scientist: return Color(red: 0.84, green: 0.72, blue: 1.00)  // #D6B8FF
        }
    }

    var gradient: Gradient {
        Gradient(colors: [softAccent, accent, deepAccent, softAccent])
    }

    var signatureExpression: WhisperEmberMascotExpression {
        switch self {
        case .auto: return resolved.signatureExpression
        case .regular: return .attentive
        case .guardian: return .happy
        case .drillSergeant: return .determined
        case .scientist: return .thinking
        }
    }

    var next: WhisperEmberCoachMode {
        switch self {
        case .auto: return .regular
        case .regular: return .guardian
        case .guardian: return .drillSergeant
        case .drillSergeant: return .scientist
        case .scientist: return .auto
        }
    }

    /// Compact tone instruction passed to the shared brain so replies match the
    /// chosen personality. Appended to `healthContext` for the turn.
    var promptInstruction: String {
        switch self {
        case .auto:
            return resolved.promptInstruction
                + "\n(Auto personality is on: Jasper chose this coach from live readiness — \(WhisperEmberAutoMood.reason))"
        case .regular:
            return "Mode: Original. Be concise, clever, data-grounded, and balanced. Normal Jasper warmth with direct next steps."
        case .guardian:
            return "Mode: Angel. Lead with protection and reassurance, reduce pressure, validate the user's effort, and give calm recovery-first next steps. Avoid harsh phrasing."
        case .drillSergeant:
            return "Mode: Drill Sergeant. Use tough-love intensity like a demanding coach: blunt, urgent, high-accountability, and energizing. Never insult the user, shame their body, or be abusive; channel the intensity into action."
        case .scientist:
            return "Mode: Scientist. Be precise, evidence-informed, and mechanism-aware. Explain the physiology and trend logic behind recommendations, quantify when useful, and keep the answer practical rather than academic."
        }
    }
}

extension Notification.Name {
    /// Posted whenever the saved Jasper personality changes — every surface
    /// (chat, meeting pill, modals) re-reads `WhisperEmberCoachMode.load()`.
    static let whisperEmberModeChanged = Notification.Name("whisperEmberModeChanged")
}
