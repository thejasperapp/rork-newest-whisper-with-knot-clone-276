import Foundation
import SwiftUI

nonisolated enum SleepStageType: String, CaseIterable, Sendable {
    case awake
    case rem
    case core
    case deep

    var displayName: String {
        switch self {
        case .awake: return "Awake"
        case .rem: return "REM"
        case .core: return "Core"
        case .deep: return "Deep"
        }
    }

    var color: Color {
        switch self {
        case .awake: return .orange
        case .rem: return .cyan
        case .core: return .indigo
        case .deep: return .purple
        }
    }

    var sortOrder: Int {
        switch self {
        case .awake: return 0
        case .rem: return 1
        case .core: return 2
        case .deep: return 3
        }
    }

    var description: String {
        switch self {
        case .awake:
            return "Brief awakenings during the night are normal. Frequent or prolonged awakenings may affect sleep quality."
        case .rem:
            return "REM (Rapid Eye Movement) sleep is crucial for memory consolidation, emotional processing, and dreaming. Adults typically spend 20-25% of sleep in REM."
        case .core:
            return "Core sleep (light sleep) makes up the majority of your night. It helps with memory, learning, and physical recovery."
        case .deep:
            return "Deep sleep is the most restorative stage. Your body repairs tissues, builds bone and muscle, and strengthens immunity. It typically occurs more in the first half of the night."
        }
    }
}

nonisolated struct SleepStageEntry: Identifiable, Sendable {
    let id: UUID
    let stage: SleepStageType
    let startDate: Date
    let endDate: Date

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    init(stage: SleepStageType, startDate: Date, endDate: Date) {
        self.id = UUID()
        self.stage = stage
        self.startDate = startDate
        self.endDate = endDate
    }
}

nonisolated struct SleepAnalysis: Sendable {
    let stages: [SleepStageEntry]
    let bedTime: Date?
    let wakeTime: Date?
    let totalSleepDuration: TimeInterval
    let remDuration: TimeInterval
    let coreDuration: TimeInterval
    let deepDuration: TimeInterval
    let awakeDuration: TimeInterval

    var sleepScore: Int {
        guard totalSleepDuration > 0 else { return 0 }
        let hoursSlept = totalSleepDuration / 3600.0
        var score = 0.0
        let durationScore = min(hoursSlept / 8.0, 1.0) * 40
        score += durationScore
        let totalAsleep = remDuration + coreDuration + deepDuration
        let remPct = totalAsleep > 0 ? remDuration / totalAsleep : 0
        let deepPct = totalAsleep > 0 ? deepDuration / totalAsleep : 0
        let remScore = min(remPct / 0.25, 1.0) * 25
        score += remScore
        let deepScore = min(deepPct / 0.20, 1.0) * 25
        score += deepScore
        let efficiencyScore = totalAsleep > 0 ? min((totalAsleep / (totalAsleep + awakeDuration)), 1.0) * 10 : 0
        score += efficiencyScore
        return min(100, Int(score))
    }

    var remPercentage: Double {
        let total = remDuration + coreDuration + deepDuration
        guard total > 0 else { return 0 }
        return remDuration / total * 100
    }

    var corePercentage: Double {
        let total = remDuration + coreDuration + deepDuration
        guard total > 0 else { return 0 }
        return coreDuration / total * 100
    }

    var deepPercentage: Double {
        let total = remDuration + coreDuration + deepDuration
        guard total > 0 else { return 0 }
        return deepDuration / total * 100
    }

    static let empty = SleepAnalysis(
        stages: [],
        bedTime: nil,
        wakeTime: nil,
        totalSleepDuration: 0,
        remDuration: 0,
        coreDuration: 0,
        deepDuration: 0,
        awakeDuration: 0
    )
}

nonisolated struct DailySleepSummary: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let analysis: SleepAnalysis

    init(date: Date, analysis: SleepAnalysis) {
        self.id = UUID()
        self.date = date
        self.analysis = analysis
    }
}

nonisolated struct WeeklyHealthSummary: Sendable {
    let startDate: Date
    let endDate: Date
    let avgSteps: Int
    let totalSteps: Int
    let avgCalories: Double
    let totalCalories: Double
    let avgSleepHours: Double
    let avgHeartRate: Double
    let avgRestingHR: Double
    let avgHRV: Double
    let totalActiveMinutes: Int
    let totalDistance: Double
    let totalWorkouts: Int
    let avgSleepScore: Int
    let dailySleep: [DailySleepSummary]
    let bestSleepDay: Date?
    let worstSleepDay: Date?

    static let empty = WeeklyHealthSummary(
        startDate: Date(), endDate: Date(),
        avgSteps: 0, totalSteps: 0, avgCalories: 0, totalCalories: 0,
        avgSleepHours: 0, avgHeartRate: 0, avgRestingHR: 0, avgHRV: 0,
        totalActiveMinutes: 0, totalDistance: 0, totalWorkouts: 0,
        avgSleepScore: 0, dailySleep: [], bestSleepDay: nil, worstSleepDay: nil
    )
}
