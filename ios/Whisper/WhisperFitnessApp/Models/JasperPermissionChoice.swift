import Foundation

nonisolated struct JasperPermissionChoice: Identifiable {
    let id: String
    let title: String

    static let options: [JasperPermissionChoice] = [
        .init(id: "read:profile", title: "Profile and achievements"),
        .init(id: "read:workouts", title: "Training and saved programs"),
        .init(id: "read:nutrition", title: "Meals, recipes and hydration"),
        .init(id: "read:sleep", title: "Sleep records"),
        .init(id: "read:vitals", title: "Heart rate, steps and readiness"),
        .init(id: "read:body", title: "Body measurements and weight"),
        .init(id: "read:bioage", title: "Exploratory biological-age estimates"),
        .init(id: "read:goals", title: "Goals"),
        .init(id: "read:charts", title: "Shared cards"),
        .init(id: "read:preferences", title: "App preferences"),
        .init(id: "read:photos", title: "Progress-photo details, not images"),
        .init(id: "read:events", title: "Updates to shared records"),
        .init(id: "read:blood", title: "Blood markers (sensitive)"),
        .init(id: "write:nutrition", title: "Save meals, recipes and grocery checks"),
        .init(id: "write:workouts", title: "Save workouts and programs"),
        .init(id: "write:goals", title: "Update goals"),
        .init(id: "write:charts", title: "Send cards to Jasper")
    ]
}
