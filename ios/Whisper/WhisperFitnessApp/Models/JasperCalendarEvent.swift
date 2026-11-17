import Foundation

nonisolated struct JasperCalendarEvent: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let start: String
    let end: String
    let allDay: Bool
    let link: String
    let source: String
}
