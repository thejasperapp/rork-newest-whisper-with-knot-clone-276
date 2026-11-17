import Foundation
import SwiftUI

nonisolated struct WorkoutData: Identifiable, Sendable {
    let id = UUID()
    let type: String
    let duration: TimeInterval
    let calories: Double
    let date: Date
    let icon: String
}

nonisolated struct SleepData: Sendable {
    let hoursSlept: Double
    let sleepQuality: String
    let bedTime: Date?
    let wakeTime: Date?
}

nonisolated struct DailyHealthSummary: Sendable {
    var steps: Int
    var calories: Double
    var activeMinutes: Int
    var heartRate: Double
    var restingHeartRate: Double
    var distance: Double
    var sleepHours: Double
    var waterIntake: Double
    var workouts: [WorkoutData]
    var vo2Max: Double
    var respiratoryRate: Double
    var bloodOxygen: Double
    var bodyMass: Double
    var bodyFatPercentage: Double
    var flightsClimbed: Int
    var standHours: Int
    var mindfulMinutes: Int
    var cyclingDistance: Double
    var heartRateVariability: Double
    var basalEnergyBurned: Double
    var walkingHeartRateAverage: Double
    var environmentalAudioExposure: Double

    static let empty = DailyHealthSummary(
        steps: 0, calories: 0, activeMinutes: 0, heartRate: 0,
        restingHeartRate: 0, distance: 0, sleepHours: 0, waterIntake: 0,
        workouts: [], vo2Max: 0, respiratoryRate: 0, bloodOxygen: 0,
        bodyMass: 0, bodyFatPercentage: 0, flightsClimbed: 0,
        standHours: 0, mindfulMinutes: 0, cyclingDistance: 0,
        heartRateVariability: 0, basalEnergyBurned: 0,
        walkingHeartRateAverage: 0, environmentalAudioExposure: 0
    )
}

nonisolated struct NutritionEntry: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let icon: String
    let time: Date
}

nonisolated struct WellnessMetric: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: String
}

nonisolated enum HealthMetricType: String, CaseIterable, Identifiable, Sendable, Hashable {
    case heartRate
    case restingHeartRate
    case steps
    case sleep
    case distance
    case calories
    case activeMinutes
    case vo2Max
    case respiratoryRate
    case bloodOxygen
    case bodyMass
    case bodyFatPercentage
    case flightsClimbed
    case standHours
    case mindfulMinutes
    case cyclingDistance
    case heartRateVariability
    case basalEnergy
    case walkingHeartRate
    case audioExposure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heartRate: return "Heart Rate"
        case .restingHeartRate: return "Resting Heart Rate"
        case .steps: return "Steps"
        case .sleep: return "Sleep"
        case .distance: return "Walking + Running"
        case .calories: return "Active Energy"
        case .activeMinutes: return "Exercise Minutes"
        case .vo2Max: return "VO₂ Max"
        case .respiratoryRate: return "Respiratory Rate"
        case .bloodOxygen: return "Blood Oxygen"
        case .bodyMass: return "Body Mass"
        case .bodyFatPercentage: return "Body Fat"
        case .flightsClimbed: return "Flights Climbed"
        case .standHours: return "Stand Hours"
        case .mindfulMinutes: return "Mindful Minutes"
        case .cyclingDistance: return "Cycling Distance"
        case .heartRateVariability: return "Heart Rate Variability"
        case .basalEnergy: return "Resting Energy"
        case .walkingHeartRate: return "Walking Avg HR"
        case .audioExposure: return "Audio Exposure"
        }
    }

    var icon: String {
        switch self {
        case .heartRate: return "heart.fill"
        case .restingHeartRate: return "heart.text.clipboard.fill"
        case .steps: return "figure.walk"
        case .sleep: return "moon.fill"
        case .distance: return "map.fill"
        case .calories: return "flame.fill"
        case .activeMinutes: return "clock.fill"
        case .vo2Max: return "lungs.fill"
        case .respiratoryRate: return "wind"
        case .bloodOxygen: return "drop.fill"
        case .bodyMass: return "scalemass.fill"
        case .bodyFatPercentage: return "percent"
        case .flightsClimbed: return "figure.stairs"
        case .standHours: return "figure.stand"
        case .mindfulMinutes: return "brain.head.profile.fill"
        case .cyclingDistance: return "figure.outdoor.cycle"
        case .heartRateVariability: return "waveform.path.ecg"
        case .basalEnergy: return "bolt.fill"
        case .walkingHeartRate: return "figure.walk.motion"
        case .audioExposure: return "ear.fill"
        }
    }

    var color: Color {
        switch self {
        case .heartRate: return .pink
        case .restingHeartRate: return .red
        case .steps: return .green
        case .sleep: return .indigo
        case .distance: return .orange
        case .calories: return .red
        case .activeMinutes: return .blue
        case .vo2Max: return .purple
        case .respiratoryRate: return .teal
        case .bloodOxygen: return .cyan
        case .bodyMass: return .brown
        case .bodyFatPercentage: return .yellow
        case .flightsClimbed: return .mint
        case .standHours: return .green
        case .mindfulMinutes: return .purple
        case .cyclingDistance: return .orange
        case .heartRateVariability: return .pink
        case .basalEnergy: return .yellow
        case .walkingHeartRate: return .red
        case .audioExposure: return .blue
        }
    }

    var unit: String {
        switch self {
        case .heartRate, .restingHeartRate, .walkingHeartRate: return "BPM"
        case .steps: return "steps"
        case .sleep: return "hrs"
        case .distance, .cyclingDistance: return "mi"
        case .calories, .basalEnergy: return "kcal"
        case .activeMinutes, .mindfulMinutes: return "min"
        case .vo2Max: return "mL/kg/min"
        case .respiratoryRate: return "br/min"
        case .bloodOxygen, .bodyFatPercentage: return "%"
        case .bodyMass: return "lbs"
        case .flightsClimbed: return "flights"
        case .standHours: return "hrs"
        case .heartRateVariability: return "ms"
        case .audioExposure: return "dB"
        }
    }

    var description: String {
        switch self {
        case .heartRate: return "Your heart rate measures how many times your heart beats per minute. A normal resting heart rate for adults is between 60 and 100 BPM."
        case .restingHeartRate: return "Resting heart rate is measured when you're still and calm. A lower resting heart rate generally indicates better cardiovascular fitness."
        case .steps: return "Steps counted throughout the day from your iPhone and Apple Watch. The general goal is 10,000 steps per day."
        case .sleep: return "Total time spent asleep including light, deep, and REM sleep stages. Adults should aim for 7-9 hours per night."
        case .distance: return "Total distance covered walking and running throughout the day."
        case .calories: return "Active energy burned through physical activity and exercise above your resting metabolic rate."
        case .activeMinutes: return "Minutes spent doing activities at or above a brisk walk. Apple recommends 30 minutes daily."
        case .vo2Max: return "VO₂ Max is the maximum amount of oxygen your body can use during exercise. Higher values indicate better cardiorespiratory fitness."
        case .respiratoryRate: return "The number of breaths you take per minute. A normal adult rate is 12-20 breaths per minute at rest."
        case .bloodOxygen: return "Blood oxygen saturation measures how much oxygen your red blood cells carry. Normal levels are typically 95-100%."
        case .bodyMass: return "Your body weight as recorded in Apple Health from manual entries or connected smart scales."
        case .bodyFatPercentage: return "The percentage of your total body mass that is fat tissue. Healthy ranges vary by age and sex."
        case .flightsClimbed: return "A flight of stairs is counted as approximately 10 feet (3 meters) of elevation gain."
        case .standHours: return "Hours in which you stood up and moved around for at least one minute. The goal is 12 stand hours per day."
        case .mindfulMinutes: return "Time spent in mindfulness or meditation sessions recorded by apps on your Apple Watch or iPhone."
        case .cyclingDistance: return "Distance covered during cycling workouts and activities."
        case .heartRateVariability: return "HRV measures the variation in time between heartbeats. Higher HRV generally indicates better recovery and fitness."
        case .basalEnergy: return "The energy your body burns at rest to maintain basic functions like breathing and circulation."
        case .walkingHeartRate: return "Your average heart rate while walking, which can indicate your overall cardiovascular health."
        case .audioExposure: return "Environmental sound levels measured by your Apple Watch. Prolonged exposure above 80 dB can cause hearing damage."
        }
    }
}

nonisolated enum DashboardWidgetType: String, CaseIterable, Identifiable, Codable, Sendable {
    case heartRate
    case steps
    case sleep
    case distance
    case calories
    case activeMinutes

    var id: String { rawValue }

    static let defaultOrder: [DashboardWidgetType] = allCases
}
