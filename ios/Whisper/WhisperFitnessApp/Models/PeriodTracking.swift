import Foundation

nonisolated struct PeriodLog: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var startDate: Date
    var endDate: Date?
    var flowIntensity: FlowIntensity
    var symptoms: [Symptom]
    var mood: Mood?
    var notes: String?
    var cervicalMucus: CervicalMucus?
    var basalBodyTemp: Double?
    var sexualActivity: SexualActivity?
    var energyLevel: Int?

    var duration: Int {
        let end = endDate ?? Date()
        return max(1, Calendar.current.dateComponents([.day], from: startDate, to: end).day ?? 1)
    }

    nonisolated enum FlowIntensity: String, Codable, Sendable, CaseIterable {
        case light = "Light"
        case medium = "Medium"
        case heavy = "Heavy"
        case spotting = "Spotting"

        var icon: String {
            switch self {
            case .light: return "drop"
            case .medium: return "drop.fill"
            case .heavy: return "drop.triangle.fill"
            case .spotting: return "drop.halffull"
            }
        }

        var color: String {
            switch self {
            case .light: return "pink"
            case .medium: return "red"
            case .heavy: return "purple"
            case .spotting: return "orange"
            }
        }
    }

    nonisolated enum CervicalMucus: String, Codable, Sendable, CaseIterable {
        case dry = "Dry"
        case sticky = "Sticky"
        case creamy = "Creamy"
        case watery = "Watery"
        case eggWhite = "Egg White"

        var icon: String {
            switch self {
            case .dry: return "sun.max.fill"
            case .sticky: return "drop.degreesign"
            case .creamy: return "cloud.fill"
            case .watery: return "drop.fill"
            case .eggWhite: return "sparkles"
            }
        }

        var fertilityIndicator: String {
            switch self {
            case .dry: return "Low fertility"
            case .sticky: return "Low fertility"
            case .creamy: return "Medium fertility"
            case .watery: return "High fertility"
            case .eggWhite: return "Peak fertility"
            }
        }
    }

    nonisolated enum SexualActivity: String, Codable, Sendable, CaseIterable {
        case protected = "Protected"
        case unprotected = "Unprotected"
        case none = "None"

        var icon: String {
            switch self {
            case .protected: return "shield.checkered"
            case .unprotected: return "heart.fill"
            case .none: return "minus.circle"
            }
        }
    }

    nonisolated enum Symptom: String, Codable, Sendable, CaseIterable {
        case cramps = "Cramps"
        case headache = "Headache"
        case bloating = "Bloating"
        case fatigue = "Fatigue"
        case backPain = "Back Pain"
        case breastTenderness = "Breast Tenderness"
        case acne = "Acne"
        case nausea = "Nausea"
        case insomnia = "Insomnia"
        case cravings = "Cravings"
        case moodSwings = "Mood Swings"
        case dizziness = "Dizziness"
        case hotFlashes = "Hot Flashes"
        case constipation = "Constipation"
        case diarrhea = "Diarrhea"
        case jointPain = "Joint Pain"

        var icon: String {
            switch self {
            case .cramps: return "bolt.fill"
            case .headache: return "brain.head.profile.fill"
            case .bloating: return "circle.dashed"
            case .fatigue: return "battery.25percent"
            case .backPain: return "figure.stand"
            case .breastTenderness: return "hand.raised.fill"
            case .acne: return "face.dashed"
            case .nausea: return "stomach"
            case .insomnia: return "moon.zzz.fill"
            case .cravings: return "fork.knife"
            case .moodSwings: return "theatermasks.fill"
            case .dizziness: return "tornado"
            case .hotFlashes: return "flame.fill"
            case .constipation: return "arrow.down.to.line"
            case .diarrhea: return "arrow.up.to.line"
            case .jointPain: return "figure.walk"
            }
        }
    }

    nonisolated enum Mood: String, Codable, Sendable, CaseIterable {
        case happy = "Happy"
        case calm = "Calm"
        case anxious = "Anxious"
        case irritable = "Irritable"
        case sad = "Sad"
        case energetic = "Energetic"
        case sensitive = "Sensitive"
        case confident = "Confident"
        case tired = "Tired"

        var emoji: String {
            switch self {
            case .happy: return "😊"
            case .calm: return "😌"
            case .anxious: return "😰"
            case .irritable: return "😤"
            case .sad: return "😢"
            case .energetic: return "⚡️"
            case .sensitive: return "🥺"
            case .confident: return "💪"
            case .tired: return "😴"
            }
        }
    }
}

nonisolated struct PeriodPrediction: Codable, Sendable {
    var nextPeriodDate: Date?
    var nextOvulationDate: Date?
    var averageCycleLength: Int
    var averagePeriodLength: Int
    var cycleDay: Int?
    var currentPhase: CyclePhase
    var fertileWindowStart: Date?
    var fertileWindowEnd: Date?
    var cycleRegularity: CycleRegularity
    var cycleLengthVariation: Int

    nonisolated enum CycleRegularity: String, Codable, Sendable {
        case regular = "Regular"
        case slightlyIrregular = "Slightly Irregular"
        case irregular = "Irregular"
        case insufficient = "Insufficient Data"
    }

    nonisolated enum CyclePhase: String, Codable, Sendable {
        case menstrual = "Menstrual"
        case follicular = "Follicular"
        case ovulation = "Ovulation"
        case luteal = "Luteal"
        case unknown = "Unknown"

        var color: String {
            switch self {
            case .menstrual: return "red"
            case .follicular: return "pink"
            case .ovulation: return "purple"
            case .luteal: return "orange"
            case .unknown: return "gray"
            }
        }

        var icon: String {
            switch self {
            case .menstrual: return "drop.fill"
            case .follicular: return "leaf.fill"
            case .ovulation: return "sparkles"
            case .luteal: return "moon.fill"
            case .unknown: return "questionmark.circle"
            }
        }

        var description: String {
            switch self {
            case .menstrual: return "Your body is shedding the uterine lining. Focus on rest, gentle movement like yoga or walking, and iron-rich foods. Stay hydrated and honor what your body needs."
            case .follicular: return "Estrogen is rising and energy levels are climbing. Great time for higher intensity workouts, trying new activities, and creative projects. Your body recovers faster during this phase."
            case .ovulation: return "Peak energy, strength, and confidence. Take advantage with challenging workouts and social activities. Cervical mucus becomes clear and stretchy — peak fertility window."
            case .luteal: return "Progesterone rises and energy may dip. Focus on moderate exercise, strength training, and recovery. Manage cravings with balanced meals rich in magnesium and complex carbs."
            case .unknown: return "Log your period to get personalized cycle insights."
            }
        }

        var nutritionTip: String {
            switch self {
            case .menstrual: return "Focus on iron-rich foods (leafy greens, red meat, legumes), vitamin C for absorption, and anti-inflammatory foods like turmeric and ginger."
            case .follicular: return "Support rising estrogen with cruciferous vegetables, lean protein, and fermented foods. Great time for lighter, energizing meals."
            case .ovulation: return "Eat antioxidant-rich foods, fiber, and healthy fats. Support liver detoxification with dark leafy greens and plenty of water."
            case .luteal: return "Combat cravings with complex carbs, magnesium-rich foods (dark chocolate, nuts), B6 sources (bananas, chickpeas), and calcium-rich foods."
            case .unknown: return "Maintain a balanced diet rich in whole foods, lean protein, and plenty of vegetables."
            }
        }

        var exerciseTip: String {
            switch self {
            case .menstrual: return "Gentle yoga, walking, light stretching. Avoid high-intensity training if you feel fatigued."
            case .follicular: return "HIIT, strength training, running, new workout classes. Your body can handle more intensity."
            case .ovulation: return "Peak performance — PR attempts, intense cardio, group fitness, competitive sports."
            case .luteal: return "Moderate strength training, pilates, swimming, walking. Reduce intensity as you approach your period."
            case .unknown: return "Listen to your body and exercise at a comfortable intensity."
            }
        }
    }

    static let empty = PeriodPrediction(
        nextPeriodDate: nil,
        nextOvulationDate: nil,
        averageCycleLength: 28,
        averagePeriodLength: 5,
        cycleDay: nil,
        currentPhase: .unknown,
        fertileWindowStart: nil,
        fertileWindowEnd: nil,
        cycleRegularity: .insufficient,
        cycleLengthVariation: 0
    )
}
