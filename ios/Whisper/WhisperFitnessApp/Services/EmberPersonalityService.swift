import Foundation
import SwiftUI

nonisolated enum EmberPersonality: String, CaseIterable, Identifiable, Sendable, Codable {
    case bestFriend = "best_friend"
    case drillSergeant = "drill_sergeant"
    case zenCoach = "zen_coach"
    case scientist = "scientist"
    case hypeBeast = "hype_beast"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bestFriend: return "Best Friend"
        case .drillSergeant: return "Drill Sergeant"
        case .zenCoach: return "Zen Coach"
        case .scientist: return "Scientist"
        case .hypeBeast: return "Hype Beast"
        }
    }

    var tagline: String {
        switch self {
        case .bestFriend: return "Warm, casual, supportive"
        case .drillSergeant: return "No excuses. Push harder."
        case .zenCoach: return "Calm, mindful, balanced"
        case .scientist: return "Data-driven, precise"
        case .hypeBeast: return "Loud energy, all caps wins"
        }
    }

    var icon: String {
        switch self {
        case .bestFriend: return "heart.fill"
        case .drillSergeant: return "flame.fill"
        case .zenCoach: return "leaf.fill"
        case .scientist: return "atom"
        case .hypeBeast: return "bolt.fill"
        }
    }

    var accent: Color {
        switch self {
        case .bestFriend: return .pink
        case .drillSergeant: return .red
        case .zenCoach: return .mint
        case .scientist: return .cyan
        case .hypeBeast: return .yellow
        }
    }

    /// Style block injected into Jasper's system prompt.
    var promptBlock: String {
        switch self {
        case .bestFriend:
            return """
            STYLE OVERRIDE — Best Friend mode:
            Talk like a warm, witty close friend. Casual contractions, light humor, genuine excitement for their wins. \
            Validate feelings first, then give the advice. Keep it human, never robotic.
            """
        case .drillSergeant:
            return """
            STYLE OVERRIDE — Drill Sergeant mode:
            Direct, intense, no fluff. Cut excuses. Use short imperative sentences. Demand action ("Get up. Move. Now."). \
            Praise only when truly earned. Never be cruel — push, don't insult. Keep responses punchy: 1-2 sentences usually.
            """
        case .zenCoach:
            return """
            STYLE OVERRIDE — Zen Coach mode:
            Calm, mindful, unhurried. Speak softly with metaphors of breath, balance, and presence. \
            Encourage reflection over hustle. Frame setbacks as part of the path. Slow the pace of the conversation.
            """
        case .scientist:
            return """
            STYLE OVERRIDE — Scientist mode:
            Precise, evidence-based, calmly technical. Reference physiology when useful (HRV, glycogen, RPE, sleep stages). \
            Quantify when possible. Cite mechanisms briefly. Never sound dry — explain like a brilliant coach who happens to have a PhD.
            """
        case .hypeBeast:
            return """
            STYLE OVERRIDE — Hype Beast mode:
            MAX ENERGY. Treat every workout, every meal hit, every PR like a championship moment. \
            Use exclamation points liberally, ALL CAPS for emphasis sparingly, vivid metaphors. \
            Pump them up but keep the actual advice accurate.
            """
        }
    }
}

@Observable
final class EmberPersonalityService {
    static let shared = EmberPersonalityService()
    private static let storeKey = "ember_personality_v1"

    var personality: EmberPersonality {
        didSet { save() }
    }

    init() {
        if let raw = AccountStorage.string(forKey: Self.storeKey),
           let p = EmberPersonality(rawValue: raw) {
            self.personality = p
        } else {
            self.personality = .bestFriend
        }
    }

    private func save() {
        AccountStorage.set(personality.rawValue, forKey: Self.storeKey)
    }

    /// Compact block to append at the END of Jasper's system prompt so the override wins.
    var promptBlock: String {
        "\n\n" + personality.promptBlock
    }
}
