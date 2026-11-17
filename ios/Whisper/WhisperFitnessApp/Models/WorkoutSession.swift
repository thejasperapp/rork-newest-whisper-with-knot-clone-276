import Foundation
import SwiftUI

nonisolated struct ExerciseLog: Identifiable, Codable, Sendable {
    let id: UUID
    let exerciseName: String
    var sets: [SetLog]
    let targetSets: Int
    let targetReps: String
    let restSeconds: Int
    var heartRateAtStart: Int
    var heartRateAtEnd: Int
    var userNotes: String
    var supersetGroupId: String?
    var isCustom: Bool

    nonisolated enum CodingKeys: String, CodingKey {
        case id, exerciseName, sets, targetSets, targetReps, restSeconds
        case heartRateAtStart, heartRateAtEnd, userNotes, supersetGroupId, isCustom
    }

    init(id: UUID, exerciseName: String, sets: [SetLog], targetSets: Int, targetReps: String, restSeconds: Int, heartRateAtStart: Int = 0, heartRateAtEnd: Int = 0, userNotes: String = "", supersetGroupId: String? = nil, isCustom: Bool = false) {
        self.id = id
        self.exerciseName = exerciseName
        self.sets = sets
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.restSeconds = restSeconds
        self.heartRateAtStart = heartRateAtStart
        self.heartRateAtEnd = heartRateAtEnd
        self.userNotes = userNotes
        self.supersetGroupId = supersetGroupId
        self.isCustom = isCustom
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        exerciseName = try container.decode(String.self, forKey: .exerciseName)
        sets = try container.decode([SetLog].self, forKey: .sets)
        targetSets = try container.decode(Int.self, forKey: .targetSets)
        targetReps = try container.decode(String.self, forKey: .targetReps)
        restSeconds = try container.decode(Int.self, forKey: .restSeconds)
        heartRateAtStart = try container.decodeIfPresent(Int.self, forKey: .heartRateAtStart) ?? 0
        heartRateAtEnd = try container.decodeIfPresent(Int.self, forKey: .heartRateAtEnd) ?? 0
        userNotes = try container.decodeIfPresent(String.self, forKey: .userNotes) ?? ""
        supersetGroupId = try container.decodeIfPresent(String.self, forKey: .supersetGroupId)
        isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}

nonisolated struct SetLog: Identifiable, Codable, Sendable {
    let id: UUID
    var weight: Double
    var reps: Int
    var isComplete: Bool
}

nonisolated struct WorkoutSessionRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let programId: UUID
    let dayName: String
    let focus: String
    let date: Date
    let duration: TimeInterval
    let exercises: [ExerciseLog]
    let averageHeartRate: Int
    let peakHeartRate: Int
    var heartRateTimeline: [HeartRatePoint]
    var caloriesBurned: Double
    var avgOxygenSaturation: Double
    var customName: String?

    var displayName: String {
        customName ?? dayName
    }

    init(id: UUID, programId: UUID, dayName: String, focus: String, date: Date, duration: TimeInterval, exercises: [ExerciseLog], averageHeartRate: Int, peakHeartRate: Int, heartRateTimeline: [HeartRatePoint] = [], caloriesBurned: Double = 0, avgOxygenSaturation: Double = 0, customName: String? = nil) {
        self.id = id
        self.programId = programId
        self.dayName = dayName
        self.focus = focus
        self.date = date
        self.duration = duration
        self.exercises = exercises
        self.averageHeartRate = averageHeartRate
        self.peakHeartRate = peakHeartRate
        self.heartRateTimeline = heartRateTimeline
        self.caloriesBurned = caloriesBurned
        self.avgOxygenSaturation = avgOxygenSaturation
        self.customName = customName
    }
}

nonisolated struct HeartRatePoint: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let bpm: Int
    let label: String

    init(id: UUID = UUID(), timestamp: Date, bpm: Int, label: String = "") {
        self.id = id
        self.timestamp = timestamp
        self.bpm = bpm
        self.label = label
    }
}

nonisolated struct DeloadRecommendation: Codable, Sendable {
    let shouldDeload: Bool
    let reason: String
    let weeksSinceLastDeload: Int
}

nonisolated struct SavedWorkoutState: Codable, Sendable {
    let programId: UUID
    let dayIndex: Int
    let exerciseLogs: [ExerciseLog]
    let currentExerciseIndex: Int
    let currentSetIndex: Int
    let elapsedSeconds: Int
    let savedAt: Date

    var isExpired: Bool {
        Date().timeIntervalSince(savedAt) > 24 * 60 * 60
    }
}
