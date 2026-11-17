import Foundation

/// Owner-only snapshot of a consented web recording; never decoded from shared meeting recaps.
nonisolated struct WhisperRecordingArchive: Decodable, Identifiable, Sendable {
    let id: String
    let owner_id: String
    let recording_id: String
    let source_revision: Int
    let state: String
    let created_at: String
    let snapshot: Snapshot

    nonisolated struct Snapshot: Decodable, Sendable {
        let version: Int
        let id: String
        let ownerId: String
        let meetingId: String?
        let title: String
        let duration: Double
        let mimeType: String
        let status: String
        let storageConsent: Bool
        let cloudConsent: Bool?
        let transcriptionState: String?
        let revision: Int
        let coverage: String
        let transcript: [Passage]
        let markers: [Marker]
        let warnings: [String]
    }
    nonisolated struct Passage: Decodable, Identifiable, Sendable {
        let id: String
        let start: Double
        let end: Double
        let text: String
        let timing: String
        let sourceId: String?
        let speakerName: String?
    }
    nonisolated struct Marker: Decodable, Identifiable, Sendable {
        let id: String
        let seconds: Double
        let title: String
        let kind: String
        let reviewed: Bool
    }
    var title: String { snapshot.title.isEmpty ? "Meeting recording" : snapshot.title }
    var isValid: Bool {
        UUID(uuidString: id) != nil && UUID(uuidString: owner_id) != nil && UUID(uuidString: recording_id) != nil
        && snapshot.version == 1 && snapshot.ownerId == owner_id && snapshot.id == recording_id
        && snapshot.storageConsent && snapshot.revision == source_revision && ["ready", "interrupted"].contains(snapshot.status)
        && ["uploading", "ready", "deleting"].contains(state) && snapshot.duration.isFinite && (0...7231).contains(snapshot.duration)
        && snapshot.transcript.count <= 20000 && snapshot.markers.count <= 300
        && Set(snapshot.transcript.map(\.id)).count == snapshot.transcript.count
        && Set(snapshot.markers.map(\.id)).count == snapshot.markers.count
        && snapshot.transcript.allSatisfy { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start && $0.end <= snapshot.duration + 1 }
        && snapshot.markers.allSatisfy { $0.seconds.isFinite && $0.seconds >= 0 && $0.seconds <= snapshot.duration + 1 }
    }
    static func time(_ seconds: Double) -> String {
        let value = Int(max(0, min(86400, seconds.isFinite ? seconds : 0)))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}
