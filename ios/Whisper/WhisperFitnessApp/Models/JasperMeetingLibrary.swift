import Foundation

nonisolated struct JasperMeetingLibrary: Codable, Sendable {
    struct Folder: Codable, Identifiable, Sendable { let id: String; let name: String }
    struct Preferences: Codable, Sendable { var focus: [String]; var instructions: String }
    let revision: Int
    let folders: [Folder]
    let filings: [String: String]
    let preferences: Preferences
}
