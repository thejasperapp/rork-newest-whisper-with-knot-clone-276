import Foundation
import SwiftUI

/// Minimal residual program payload used by `WhisperBackendService` to decode
/// legacy `kind: "program"` post embeds shared from older Whisper clients.
/// The full Whisper program builder/UX has been retired now that Whisper is
/// a pure social app — this struct exists only so historical posts decode
/// cleanly and can be flattened into Whisper's own program embed view.

nonisolated enum BodyGoal: String, CaseIterable, Identifiable, Codable, Sendable {
    case muscleGain = "Build Muscle"
    case fatLoss = "Lose Fat"
    case endurance = "Improve Endurance"
    case strength = "Get Stronger"
    case flexibility = "Increase Flexibility"
    case athletic = "Athletic Performance"
    case toneUp = "Tone & Define"
    case generalFitness = "General Fitness"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .muscleGain: return "dumbbell.fill"
        case .fatLoss: return "flame.fill"
        case .endurance: return "figure.run"
        case .strength: return "figure.strengthtraining.traditional"
        case .flexibility: return "figure.yoga"
        case .athletic: return "figure.mixed.cardio"
        case .toneUp: return "figure.cooldown"
        case .generalFitness: return "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .muscleGain: return .purple
        case .fatLoss: return .orange
        case .endurance: return .green
        case .strength: return .red
        case .flexibility: return .teal
        case .athletic: return .blue
        case .toneUp: return .pink
        case .generalFitness: return .mint
        }
    }

    var subtitle: String {
        switch self {
        case .muscleGain: return "Hypertrophy focused training"
        case .fatLoss: return "High calorie burn programs"
        case .endurance: return "Cardio & stamina building"
        case .strength: return "Heavy compound lifts"
        case .flexibility: return "Mobility & stretch routines"
        case .athletic: return "Speed, agility & power"
        case .toneUp: return "Lean muscle definition"
        case .generalFitness: return "Balanced wellness approach"
        }
    }
}

nonisolated struct GeneratedProgram: Identifiable, Codable, Sendable {
    let id: UUID
    let goal: BodyGoal
    var title: String
    let overview: String
    let weeks: Int
    let daysPerWeek: Int
    var workoutDays: [ProgramDay]
    let createdAt: Date
}

nonisolated struct ProgramDay: Identifiable, Codable, Sendable {
    let id: UUID
    let dayName: String
    let focus: String
    var exercises: [ProgramExercise]
}

nonisolated struct ProgramExercise: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let sets: Int
    let reps: String
    let restSeconds: Int
    let notes: String
    var gifUrl: String?
    var supersetGroupId: String?
}
