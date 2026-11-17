import CoreSpotlight
import UniformTypeIdentifiers

enum SpotlightService {
    static let domainID = "app.rork.jasper"

    enum IndexableItem: String, CaseIterable {
        case home = "jasper.home"
        case workouts = "jasper.workouts"
        case wellness = "jasper.wellness"
        case nutrition = "jasper.nutrition"
        case ember = "jasper.ember"
        case sleep = "jasper.sleep"
        case meditation = "jasper.meditation"
        case journal = "jasper.journal"

        var title: String {
            switch self {
            case .home: return "Whisper Dashboard"
            case .workouts: return "Workouts"
            case .wellness: return "Wellness & Recovery"
            case .nutrition: return "Nutrition Tracker"
            case .ember: return "Ask Jasper"
            case .sleep: return "Sleep Analysis"
            case .meditation: return "Meditation"
            case .journal: return "Wellness Journal"
            }
        }

        var contentDescription: String {
            switch self {
            case .home: return "View your daily fitness overview, steps, heart rate, and activity rings"
            case .workouts: return "Start a workout, browse programs, and track your training"
            case .wellness: return "Check wellness metrics, sleep, heart rate variability, and recovery"
            case .nutrition: return "Log meals, track macros, and monitor water intake"
            case .ember: return "Chat with Jasper, your fitness assistant"
            case .sleep: return "View detailed sleep analysis and sleep score"
            case .meditation: return "Start a guided meditation or breathing session"
            case .journal: return "Write in your wellness journal and track your mood"
            }
        }

        var keywords: [String] {
            switch self {
            case .home: return ["fitness", "dashboard", "steps", "heart rate", "activity", "health"]
            case .workouts: return ["workout", "exercise", "training", "gym", "strength", "cardio", "running"]
            case .wellness: return ["wellness", "recovery", "HRV", "stress", "health", "period"]
            case .nutrition: return ["nutrition", "food", "calories", "protein", "macros", "diet", "water"]
            case .ember: return ["ember", "assistant", "coach", "advice", "fitness coach"]
            case .sleep: return ["sleep", "rest", "sleep score", "bedtime", "sleep analysis"]
            case .meditation: return ["meditation", "mindfulness", "breathing", "calm", "relax"]
            case .journal: return ["journal", "mood", "diary", "feelings", "wellness journal"]
            }
        }

        var tabIndex: Int? {
            switch self {
            case .home: return 0
            case .workouts: return 1
            case .wellness: return 2
            case .nutrition: return 3
            case .ember, .sleep, .meditation, .journal: return nil
            }
        }
    }

    static func indexAllItems() {
        let items = IndexableItem.allCases.map { item -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = item.title
            attributes.contentDescription = item.contentDescription
            attributes.keywords = item.keywords

            return CSSearchableItem(
                uniqueIdentifier: item.rawValue,
                domainIdentifier: domainID,
                attributeSet: attributes
            )
        }

        CSSearchableIndex.default().indexSearchableItems(items)
    }

    static func deleteAllItems() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainID])
    }
}
