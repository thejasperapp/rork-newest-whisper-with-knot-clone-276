import Foundation
import CoreLocation
import SwiftUI

nonisolated struct Race: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var distance: Double
    var startDate: String
    var status: String
    var joinCode: String
    var organizerName: String
    var startLatitude: Double?
    var startLongitude: Double?
    var finishLatitude: Double?
    var finishLongitude: Double?
    var raceStartedAt: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, distance, status
        case startDate = "start_date"
        case joinCode = "join_code"
        case organizerName = "organizer_name"
        case startLatitude = "start_latitude"
        case startLongitude = "start_longitude"
        case finishLatitude = "finish_latitude"
        case finishLongitude = "finish_longitude"
        case raceStartedAt = "race_started_at"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        distance = try container.decode(Double.self, forKey: .distance)
        startDate = try container.decode(String.self, forKey: .startDate)
        status = try container.decode(String.self, forKey: .status)
        joinCode = try container.decode(String.self, forKey: .joinCode)
        organizerName = try container.decode(String.self, forKey: .organizerName)
        startLatitude = try container.decodeIfPresent(Double.self, forKey: .startLatitude)
        startLongitude = try container.decodeIfPresent(Double.self, forKey: .startLongitude)
        finishLatitude = try container.decodeIfPresent(Double.self, forKey: .finishLatitude)
        finishLongitude = try container.decodeIfPresent(Double.self, forKey: .finishLongitude)
        raceStartedAt = try container.decodeIfPresent(String.self, forKey: .raceStartedAt)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    init(id: String, name: String, distance: Double, startDate: String, status: String, joinCode: String, organizerName: String, startLatitude: Double? = nil, startLongitude: Double? = nil, finishLatitude: Double? = nil, finishLongitude: Double? = nil, raceStartedAt: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.name = name
        self.distance = distance
        self.startDate = startDate
        self.status = status
        self.joinCode = joinCode
        self.organizerName = organizerName
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.finishLatitude = finishLatitude
        self.finishLongitude = finishLongitude
        self.raceStartedAt = raceStartedAt
        self.createdAt = createdAt
    }

    var raceStatus: RaceStatus {
        RaceStatus(rawValue: status) ?? .upcoming
    }

    var raceStartedDate: Date? {
        guard let str = raceStartedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: str)
    }

    func distanceFormatted(useMiles: Bool = false) -> String {
        if !useMiles {
            if distance == 5.0 { return "5K" }
            if distance == 10.0 { return "10K" }
            if distance == 21.1 { return "Half Marathon" }
            if distance == 42.2 { return "Marathon" }
            return String(format: "%.1f km", distance)
        } else {
            let miles = distance * 0.621371
            if distance == 5.0 { return "5K (3.1 mi)" }
            if distance == 10.0 { return "10K (6.2 mi)" }
            if distance == 21.1 { return "Half Marathon" }
            if distance == 42.2 { return "Marathon" }
            return String(format: "%.1f mi", miles)
        }
    }

    var distanceFormatted: String {
        distanceFormatted(useMiles: false)
    }

    var startCoordinate: CLLocationCoordinate2D? {
        guard let lat = startLatitude, let lng = startLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var finishCoordinate: CLLocationCoordinate2D? {
        guard let lat = finishLatitude, let lng = finishLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

nonisolated enum RaceStatus: String, Codable, Sendable {
    case upcoming
    case active
    case finished
}

nonisolated struct RaceParticipant: Codable, Identifiable, Sendable {
    let id: String
    let raceId: String
    var displayName: String
    var bibNumber: Int?
    var role: String
    var status: String
    var finishTimeSeconds: Double?
    var averagePace: Double?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case raceId = "race_id"
        case displayName = "display_name"
        case bibNumber = "bib_number"
        case role, status
        case finishTimeSeconds = "finish_time_seconds"
        case averagePace = "average_pace"
        case createdAt = "created_at"
    }

    var participantRole: ParticipantRole {
        ParticipantRole(rawValue: role) ?? .runner
    }

    var participantStatus: ParticipantStatus {
        ParticipantStatus(rawValue: status) ?? .registered
    }

    var finishTimeFormatted: String? {
        guard let seconds = finishTimeSeconds else { return nil }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    var paceFormatted: String? {
        guard let pace = averagePace else { return nil }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}

nonisolated enum ParticipantRole: String, Codable, Sendable {
    case runner
    case spectator
    case organizer
}

nonisolated enum ParticipantStatus: String, Codable, Sendable {
    case registered
    case running
    case finished
    case dnf
}

nonisolated struct RunnerPosition: Codable, Sendable {
    let participantId: String
    var raceId: String?
    let displayName: String
    let latitude: Double
    let longitude: Double
    let speed: Double
    let distanceCovered: Double
    let timestamp: Double

    enum CodingKeys: String, CodingKey {
        case participantId = "participant_id"
        case raceId = "race_id"
        case displayName = "display_name"
        case latitude, longitude, speed
        case distanceCovered = "distance_covered"
        case timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var speedKmh: Double {
        speed * 3.6
    }

    var paceMinPerKm: Double? {
        guard speed > 0 else { return nil }
        return 1000.0 / speed / 60.0
    }
}
