import Foundation

nonisolated struct WhisperMeetAgendaItem: Identifiable {
    let id: String
    let title: String
    let start: Date
    let subtitle: String
    let link: String?
    let meeting: WhisperMeetingRow?
    let group: String
}
