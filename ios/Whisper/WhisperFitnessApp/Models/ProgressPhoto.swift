import Foundation
import SwiftUI

nonisolated struct ProgressPhoto: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let imageData: Data
    let pose: PhotoPose
    var weight: Double?
    var note: String?

    init(id: UUID = UUID(), date: Date = Date(), imageData: Data, pose: PhotoPose, weight: Double? = nil, note: String? = nil) {
        self.id = id
        self.date = date
        self.imageData = imageData
        self.pose = pose
        self.weight = weight
        self.note = note
    }
}

nonisolated enum PhotoPose: String, Codable, CaseIterable, Identifiable, Sendable {
    case front = "Front"
    case side = "Side"
    case back = "Back"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .front: return "person.fill"
        case .side: return "person.fill.turn.right"
        case .back: return "person.fill.turn.left"
        }
    }

    var color: Color {
        switch self {
        case .front: return .blue
        case .side: return .purple
        case .back: return .orange
        }
    }

    var guide: String {
        switch self {
        case .front: return "Stand facing the camera, arms relaxed at your sides"
        case .side: return "Stand sideways to the camera, arms relaxed"
        case .back: return "Stand with your back to the camera, arms relaxed"
        }
    }
}
